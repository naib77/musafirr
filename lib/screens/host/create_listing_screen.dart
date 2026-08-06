import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/utils/responsive.dart';
import '../../data/facility_catalog.dart';
import '../../models/listing.dart';
import '../../models/listing_type.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/image_upload_service.dart';
import '../../state/auth_state.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/image_picker_grid.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/modern_banner.dart';
import 'listing_pricing_fields.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({
    super.key,
    required this.repository,
    required this.authState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 8;

  // Form data
  ListingType _propertyType = ListingType.room;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  // Structured (Airbnb-style) address parts.
  final _flatFloorController = TextEditingController();
  final _houseNoController = TextEditingController();
  final _streetController = TextEditingController();
  final _areaController = TextEditingController();
  final _cityController = TextEditingController(text: 'Dhaka');
  final _postalCodeController = TextEditingController();
  final _landmarkController = TextEditingController();
  double _latitude = 23.7806;
  double _longitude = 90.4070;
  int _maxGuests = 2;
  int _bedrooms = 1;
  int _beds = 1;
  int _bathrooms = 1;
  final Set<String> _selectedAmenities = {'Wi-Fi', 'Attached Bath'};
  final _hourlyPriceController = TextEditingController(text: '150');
  final _dailyPriceController = TextEditingController(text: '1500');
  final _monthlyPriceController = TextEditingController(text: '35000');

  // Which booking plans this listing offers. New listings start with all on;
  // a host turns off the plans they don't offer (at least one must stay on).
  bool _hourlyEnabled = true;
  bool _dailyEnabled = true;
  bool _monthlyEnabled = true;

  // Per-plan min/max booking duration (min defaults to 1, max blank = no cap).
  final _minHoursController = TextEditingController(text: '1');
  final _maxHoursController = TextEditingController();
  final _minNightsController = TextEditingController(text: '1');
  final _maxNightsController = TextEditingController();
  final _minMonthsController = TextEditingController(text: '1');
  final _maxMonthsController = TextEditingController();

  // House rules
  final _checkInTimeController = TextEditingController(text: '2:00 PM');
  final _checkOutTimeController = TextEditingController(text: '11:00 AM');
  bool _smokingAllowed = false;
  bool _petsAllowed = false;
  bool _partiesAllowed = false;
  final _quietHoursController = TextEditingController();
  final _additionalRulesController = TextEditingController();

  // Check-in & access (private — host-only, delivered via pre-check-in message)
  final _directionsController = TextEditingController();
  final _wifiNameController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  final _accessCodeController = TextEditingController();

  // Image data
  List<SelectedImage> _selectedImages = [];
  bool _isUploadingImages = false;
  String? _uploadError;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _pageController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _flatFloorController.dispose();
    _houseNoController.dispose();
    _streetController.dispose();
    _areaController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _landmarkController.dispose();
    _hourlyPriceController.dispose();
    _dailyPriceController.dispose();
    _monthlyPriceController.dispose();
    _minHoursController.dispose();
    _maxHoursController.dispose();
    _minNightsController.dispose();
    _maxNightsController.dispose();
    _minMonthsController.dispose();
    _maxMonthsController.dispose();
    _checkInTimeController.dispose();
    _checkOutTimeController.dispose();
    _quietHoursController.dispose();
    _additionalRulesController.dispose();
    _directionsController.dispose();
    _wifiNameController.dispose();
    _wifiPasswordController.dispose();
    _accessCodeController.dispose();
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
        return _streetController.text.trim().isNotEmpty &&
            _areaController.text.trim().isNotEmpty &&
            _cityController.text.trim().isNotEmpty;
      case 3: // Details
        return _maxGuests > 0 && _bedrooms > 0 && _beds > 0 && _bathrooms > 0;
      case 4: // Pricing
        return _pricingError() == null;
      case 5: // House rules — all optional
        return true;
      case 6: // Check-in & access — all optional
        return true;
      case 7: // Photos
        return _selectedImages.isNotEmpty && !_isUploadingImages;
      default:
        return false;
    }
  }

  /// Validates the pricing step. Returns a user-facing message, or null if valid.
  ///
  /// Rules: at least one plan enabled, each enabled plan has a positive rate,
  /// and rates strictly increase by duration (hourly < daily < monthly) among
  /// the enabled plans.
  String? _pricingError() {
    return validatePlanRates(
      hourlyEnabled: _hourlyEnabled,
      dailyEnabled: _dailyEnabled,
      monthlyEnabled: _monthlyEnabled,
      hourlyText: _hourlyPriceController.text,
      dailyText: _dailyPriceController.text,
      monthlyText: _monthlyPriceController.text,
    );
  }

  Future<void> _submitListing() async {
    if (!_canProceed()) return;

    setState(() {
      _isSubmitting = true;
      _isUploadingImages = true;
      _uploadError = null;
    });

    try {
      final user = widget.authState.currentUser;
      final hourlyRate =
          _hourlyEnabled ? double.parse(_hourlyPriceController.text) : null;
      final dailyRate =
          _dailyEnabled ? double.parse(_dailyPriceController.text) : null;
      final monthlyRate =
          _monthlyEnabled ? double.parse(_monthlyPriceController.text) : null;

      // Generate listing ID first (needed for image upload path)
      final listingId = 'listing_${DateTime.now().millisecondsSinceEpoch}';

      // Upload images to Supabase Storage
      final uploadService = ImageUploadService.instance;
      final imageUrls = <String>[];

      for (var i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];

        // Update progress
        setState(() {
          _selectedImages[i] = image.copyWith(
            isUploading: true,
            uploadProgress: 0,
          );
        });

        // Upload image
        final xFile = XFile(image.localPath!);
        final result = await uploadService.uploadListingImage(
          image: xFile,
          listingId: listingId,
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _selectedImages[i] = _selectedImages[i].copyWith(
                  uploadProgress: progress,
                );
              });
            }
          },
        );

        if (result.success && result.publicUrl != null) {
          imageUrls.add(result.publicUrl!);
          setState(() {
            _selectedImages[i] = image.copyWith(
              isUploading: false,
              uploadedUrl: result.publicUrl,
              storagePath: result.storagePath,
            );
          });
        } else {
          setState(() {
            _selectedImages[i] = image.copyWith(
              isUploading: false,
              error: result.errorMessage ?? 'Upload failed',
            );
          });
          throw Exception(
              'Failed to upload image ${i + 1}: ${result.errorMessage}');
        }
      }

      final listing = Listing(
        id: listingId,
        hostId: user?.id,
        ownerName: user?.name ?? 'Host',
        hostAvatarUrl: user?.avatarUrl,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        address: Listing.composeAddress(
          houseNo: _houseNoController.text,
          flatFloor: _flatFloorController.text,
          street: _streetController.text,
          area: _areaController.text,
          city: _cityController.text,
          postalCode: _postalCodeController.text,
        ),
        city: _cityController.text.trim(),
        country: 'Bangladesh',
        flatFloor: _emptyToNull(_flatFloorController.text),
        houseNo: _emptyToNull(_houseNoController.text),
        street: _emptyToNull(_streetController.text),
        area: _emptyToNull(_areaController.text),
        postalCode: _emptyToNull(_postalCodeController.text),
        landmark: _emptyToNull(_landmarkController.text),
        type: _propertyType,
        latitude: _latitude,
        longitude: _longitude,
        hourlyRate: hourlyRate,
        dailyRate: dailyRate,
        monthlyRate: monthlyRate,
        imageUrls: imageUrls,
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
        bookingLimits: BookingLimits(
          minHours:
              _hourlyEnabled ? int.tryParse(_minHoursController.text) : null,
          maxHours:
              _hourlyEnabled ? int.tryParse(_maxHoursController.text) : null,
          minNights:
              _dailyEnabled ? int.tryParse(_minNightsController.text) : null,
          maxNights:
              _dailyEnabled ? int.tryParse(_maxNightsController.text) : null,
          minMonths:
              _monthlyEnabled ? int.tryParse(_minMonthsController.text) : null,
          maxMonths:
              _monthlyEnabled ? int.tryParse(_maxMonthsController.text) : null,
        ),
        houseRules: HouseRules(
          checkInTime: _emptyToNull(_checkInTimeController.text),
          checkOutTime: _emptyToNull(_checkOutTimeController.text),
          smokingAllowed: _smokingAllowed,
          petsAllowed: _petsAllowed,
          partiesAllowed: _partiesAllowed,
          quietHours: _emptyToNull(_quietHoursController.text),
          additionalRules: _emptyToNull(_additionalRulesController.text),
        ),
        checkInDetails: CheckInDetails(
          directions: _emptyToNull(_directionsController.text),
          wifiName: _emptyToNull(_wifiNameController.text),
          wifiPassword: _emptyToNull(_wifiPasswordController.text),
          accessCode: _emptyToNull(_accessCodeController.text),
        ),
      );

      // Add to repository — await so a failed insert surfaces below instead
      // of showing a success banner for a listing that was never created.
      await widget.repository.addListing(listing);

      if (mounted) {
        Navigator.pop(context);
        ModernBanner.showSuccess(context, 'Listing created successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadError = e.toString());
        ModernBanner.showError(context, 'Failed to create listing: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isUploadingImages = false;
        });
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
      body: ResponsiveCenter(
        maxWidth: 760,
        child: Column(
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
                  flatFloorController: _flatFloorController,
                  houseNoController: _houseNoController,
                  streetController: _streetController,
                  areaController: _areaController,
                  cityController: _cityController,
                  postalCodeController: _postalCodeController,
                  landmarkController: _landmarkController,
                  latitude: _latitude,
                  longitude: _longitude,
                  onLocationChanged: (lat, lng, address) {
                    setState(() {
                      _latitude = lat;
                      _longitude = lng;
                      // Seed Road/Street from the reverse-geocoded address only
                      // if the host hasn't typed one — a helpful starting point.
                      if (address != null &&
                          _streetController.text.trim().isEmpty) {
                        _streetController.text = address;
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
                  hourlyPriceController: _hourlyPriceController,
                  dailyPriceController: _dailyPriceController,
                  monthlyPriceController: _monthlyPriceController,
                  hourlyEnabled: _hourlyEnabled,
                  dailyEnabled: _dailyEnabled,
                  monthlyEnabled: _monthlyEnabled,
                  onHourlyToggled: (v) => setState(() => _hourlyEnabled = v),
                  onDailyToggled: (v) => setState(() => _dailyEnabled = v),
                  onMonthlyToggled: (v) => setState(() => _monthlyEnabled = v),
                  onChanged: () => setState(() {}),
                  errorText: _pricingError(),
                  minHoursController: _minHoursController,
                  maxHoursController: _maxHoursController,
                  minNightsController: _minNightsController,
                  maxNightsController: _maxNightsController,
                  minMonthsController: _minMonthsController,
                  maxMonthsController: _maxMonthsController,
                ),
                _HouseRulesStep(
                  checkInTimeController: _checkInTimeController,
                  checkOutTimeController: _checkOutTimeController,
                  quietHoursController: _quietHoursController,
                  additionalRulesController: _additionalRulesController,
                  smokingAllowed: _smokingAllowed,
                  petsAllowed: _petsAllowed,
                  partiesAllowed: _partiesAllowed,
                  onSmokingToggled: (v) => setState(() => _smokingAllowed = v),
                  onPetsToggled: (v) => setState(() => _petsAllowed = v),
                  onPartiesToggled: (v) => setState(() => _partiesAllowed = v),
                ),
                _CheckInAccessStep(
                  directionsController: _directionsController,
                  wifiNameController: _wifiNameController,
                  wifiPasswordController: _wifiPasswordController,
                  accessCodeController: _accessCodeController,
                ),
                _PhotosStep(
                  images: _selectedImages,
                  onImagesChanged: (images) {
                    setState(() => _selectedImages = images);
                  },
                  isUploading: _isUploadingImages,
                  error: _uploadError,
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
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: descriptionController,
            label: 'Description (optional)',
            hint: 'Describe the unique features of your space...',
            maxLines: 5,
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

// Step 3: Location
class _LocationStep extends StatelessWidget {
  const _LocationStep({
    required this.flatFloorController,
    required this.houseNoController,
    required this.streetController,
    required this.areaController,
    required this.cityController,
    required this.postalCodeController,
    required this.landmarkController,
    required this.latitude,
    required this.longitude,
    required this.onLocationChanged,
    required this.onChanged,
  });

  final TextEditingController flatFloorController;
  final TextEditingController houseNoController;
  final TextEditingController streetController;
  final TextEditingController areaController;
  final TextEditingController cityController;
  final TextEditingController postalCodeController;
  final TextEditingController landmarkController;
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
            'Your exact address is only shared with guests after they book.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          AppTextField(
            controller: houseNoController,
            label: 'House / Building no.',
            hint: 'e.g., House 12',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: flatFloorController,
            label: 'Flat / Floor (optional)',
            hint: 'e.g., B-4, 3rd floor',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: streetController,
            label: 'Road / Street',
            hint: 'e.g., Road 27',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: areaController,
            label: 'Area / Locality',
            hint: 'e.g., Banani',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: cityController,
            label: 'City',
            hint: 'e.g., Dhaka',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: postalCodeController,
            label: 'Postal code (optional)',
            hint: 'e.g., 1213',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: landmarkController,
            label: 'Landmark (optional)',
            hint: 'e.g., Near Banani Bridge',
            onChanged: (_) => onChanged(),
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
          const SizedBox(height: 4),
          Text(
            'What does your place offer?',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          // Amenities grouped by category (Essentials / Features / Power / Safety).
          for (final group in FacilityCatalog.groups) ...[
            const SizedBox(height: 12),
            Text(
              group.title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: group.facilities.map((facility) {
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
    required this.hourlyPriceController,
    required this.dailyPriceController,
    required this.monthlyPriceController,
    required this.hourlyEnabled,
    required this.dailyEnabled,
    required this.monthlyEnabled,
    required this.onHourlyToggled,
    required this.onDailyToggled,
    required this.onMonthlyToggled,
    required this.onChanged,
    required this.errorText,
    required this.minHoursController,
    required this.maxHoursController,
    required this.minNightsController,
    required this.maxNightsController,
    required this.minMonthsController,
    required this.maxMonthsController,
  });

  final TextEditingController hourlyPriceController;
  final TextEditingController dailyPriceController;
  final TextEditingController monthlyPriceController;
  final bool hourlyEnabled;
  final bool dailyEnabled;
  final bool monthlyEnabled;
  final ValueChanged<bool> onHourlyToggled;
  final ValueChanged<bool> onDailyToggled;
  final ValueChanged<bool> onMonthlyToggled;
  final VoidCallback onChanged;
  final String? errorText;
  final TextEditingController minHoursController;
  final TextEditingController maxHoursController;
  final TextEditingController minNightsController;
  final TextEditingController maxNightsController;
  final TextEditingController minMonthsController;
  final TextEditingController maxMonthsController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set your prices',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose which booking plans you offer and set a rate for each. '
            'Turn off any you don\'t offer — at least one must stay on.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // Hourly rate
          PlanPriceRow(
            controller: hourlyPriceController,
            label: 'Hourly rate',
            icon: Icons.schedule,
            hint: '150',
            helperText: 'For short stays (1-12 hours)',
            enabled: hourlyEnabled,
            onToggled: onHourlyToggled,
            onChanged: onChanged,
            minController: minHoursController,
            maxController: maxHoursController,
            unitLabel: 'hours',
          ),
          const SizedBox(height: 20),

          // Daily rate
          PlanPriceRow(
            controller: dailyPriceController,
            label: 'Daily rate (per night)',
            icon: Icons.today,
            hint: '1500',
            helperText: 'For overnight stays',
            enabled: dailyEnabled,
            onToggled: onDailyToggled,
            onChanged: onChanged,
            minController: minNightsController,
            maxController: maxNightsController,
            unitLabel: 'nights',
          ),
          const SizedBox(height: 20),

          // Monthly rate
          PlanPriceRow(
            controller: monthlyPriceController,
            label: 'Monthly rate',
            icon: Icons.calendar_month,
            hint: '35000',
            helperText: 'For long-term stays (1+ months)',
            enabled: monthlyEnabled,
            onToggled: onMonthlyToggled,
            onChanged: onChanged,
            minController: minMonthsController,
            maxController: maxMonthsController,
            unitLabel: 'months',
          ),

          if (errorText != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.error_outline,
                    size: 18, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorText!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),

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
                    '• Hourly: Great for meeting rooms, workspaces\n'
                    '• Daily: Standard vacation rental pricing\n'
                    '• Monthly: Offer a discount for long-term stays',
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

// Step 6: Photos
class _PhotosStep extends StatelessWidget {
  const _PhotosStep({
    required this.images,
    required this.onImagesChanged,
    required this.isUploading,
    this.error,
  });

  final List<SelectedImage> images;
  final ValueChanged<List<SelectedImage>> onImagesChanged;
  final bool isUploading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add some photos',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Great photos help guests imagine staying at your place. Add at least 1 photo to get started.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // Image picker grid
          ImagePickerGrid(
            images: images,
            onImagesChanged: onImagesChanged,
            maxImages: 10,
            enabled: !isUploading,
          ),

          // Error message
          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Tips card
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
                        'Photo tips',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Use natural lighting when possible\n'
                    '• Show the whole room in wide shots\n'
                    '• Highlight unique features\n'
                    '• Keep spaces clean and uncluttered\n'
                    '• First photo will be your cover image',
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

/// Trims a text field and returns null when empty, so blank optional fields
/// are stored as NULL rather than ''.
String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

// Step 6: House rules
class _HouseRulesStep extends StatelessWidget {
  const _HouseRulesStep({
    required this.checkInTimeController,
    required this.checkOutTimeController,
    required this.quietHoursController,
    required this.additionalRulesController,
    required this.smokingAllowed,
    required this.petsAllowed,
    required this.partiesAllowed,
    required this.onSmokingToggled,
    required this.onPetsToggled,
    required this.onPartiesToggled,
  });

  final TextEditingController checkInTimeController;
  final TextEditingController checkOutTimeController;
  final TextEditingController quietHoursController;
  final TextEditingController additionalRulesController;
  final bool smokingAllowed;
  final bool petsAllowed;
  final bool partiesAllowed;
  final ValueChanged<bool> onSmokingToggled;
  final ValueChanged<bool> onPetsToggled;
  final ValueChanged<bool> onPartiesToggled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'House rules',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Set expectations for guests. All optional — leave blank to skip.',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: checkInTimeController,
                  label: 'Check-in time',
                  hint: 'e.g. 2:00 PM',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  controller: checkOutTimeController,
                  label: 'Check-out time',
                  hint: 'e.g. 11:00 AM',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Smoking allowed'),
            value: smokingAllowed,
            onChanged: onSmokingToggled,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pets allowed'),
            value: petsAllowed,
            onChanged: onPetsToggled,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Parties / events allowed'),
            value: partiesAllowed,
            onChanged: onPartiesToggled,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: quietHoursController,
            label: 'Quiet hours (optional)',
            hint: 'e.g. 10:00 PM – 7:00 AM',
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: additionalRulesController,
            label: 'Additional rules (optional)',
            hint: 'Anything else guests should know',
            maxLines: 4,
          ),
        ],
      ),
    );
  }
}

// Step 7: Check-in & access (private — host-only)
class _CheckInAccessStep extends StatelessWidget {
  const _CheckInAccessStep({
    required this.directionsController,
    required this.wifiNameController,
    required this.wifiPasswordController,
    required this.accessCodeController,
  });

  final TextEditingController directionsController;
  final TextEditingController wifiNameController;
  final TextEditingController wifiPasswordController;
  final TextEditingController accessCodeController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Check-in & access',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'These details are private. They are shared with a guest only after '
            'their booking is confirmed, in their check-in message.',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Never shown publicly on your listing.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppTextField(
            controller: directionsController,
            label: 'Directions to the place (optional)',
            hint: 'Landmarks, floor, which gate to use…',
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: wifiNameController,
            label: 'Wi-Fi network name (optional)',
            hint: 'e.g. Musafir_5G',
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: wifiPasswordController,
            label: 'Wi-Fi password (optional)',
            hint: 'Shared only with confirmed guests',
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: accessCodeController,
            label: 'Door / access code (optional)',
            hint: 'e.g. 1234# or lockbox code',
          ),
        ],
      ),
    );
  }
}
