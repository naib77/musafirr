import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/utils/responsive.dart';
import '../../data/facility_catalog.dart';
import '../../models/listing.dart';
import '../../models/listing_purpose.dart';
import '../../models/listing_type.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/image_upload_service.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/image_picker_grid.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/modern_banner.dart';
import '../../widgets/purpose_selector.dart';
import 'listing_pricing_fields.dart';

/// Single-scroll form for editing an existing listing.
///
/// All sections (basics, type, location, details, pricing, photos) are editable
/// inline with one Save action. Reuses the create flow's field widgets and the
/// shared pricing validator/toggle row so the two stay in sync.
class EditListingScreen extends StatefulWidget {
  const EditListingScreen({
    super.key,
    required this.repository,
    required this.listing,
  });

  final MusafirRepository repository;
  final Listing listing;

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  // Structured (Airbnb-style) address parts.
  late final TextEditingController _flatFloorController;
  late final TextEditingController _houseNoController;
  late final TextEditingController _streetController;
  late final TextEditingController _areaController;
  late final TextEditingController _cityController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _landmarkController;
  late final TextEditingController _hourlyPriceController;
  late final TextEditingController _dailyPriceController;
  late final TextEditingController _monthlyPriceController;

  late ListingType _propertyType;
  late Set<ListingPurpose> _selectedPurposes;
  late double _latitude;
  late double _longitude;
  late int _maxGuests;
  late int _bedrooms;
  late int _beds;
  late int _bathrooms;
  late Set<String> _selectedAmenities;

  late bool _hourlyEnabled;
  late bool _dailyEnabled;
  late bool _monthlyEnabled;

  // Per-plan min/max booking duration.
  late final TextEditingController _minHoursController;
  late final TextEditingController _maxHoursController;
  late final TextEditingController _minNightsController;
  late final TextEditingController _maxNightsController;
  late final TextEditingController _minMonthsController;
  late final TextEditingController _maxMonthsController;

  // House rules
  late final TextEditingController _checkInTimeController;
  late final TextEditingController _checkOutTimeController;
  late final TextEditingController _quietHoursController;
  late final TextEditingController _additionalRulesController;
  late bool _smokingAllowed;
  late bool _petsAllowed;
  late bool _partiesAllowed;

  // Check-in & access (private)
  late final TextEditingController _directionsController;
  late final TextEditingController _wifiNameController;
  late final TextEditingController _wifiPasswordController;
  late final TextEditingController _accessCodeController;

  late List<SelectedImage> _images;
  late List<String> _originalImageUrls;

  bool _isSaving = false;

  // Tracks whether the host has made any change that isn't saved yet, so a
  // back-navigation can warn before discarding. [_trackChanges] gates it off
  // during programmatic seeding (check-in load) and save teardown.
  bool _dirty = false;
  bool _trackChanges = true;

  // Every field edit in this form flows through setState (directly for toggles/
  // counters/photos, and via the text-controller listeners added in initState),
  // so marking dirty here catches them all — including future fields.
  @override
  void setState(VoidCallback fn) {
    if (_trackChanges) _dirty = true;
    super.setState(fn);
  }

  void _markDirty() {
    if (_trackChanges) _dirty = true;
  }

  @override
  void initState() {
    super.initState();
    final l = widget.listing;
    _titleController = TextEditingController(text: l.title);
    _descriptionController = TextEditingController(text: l.description ?? '');
    // House / flat / road no longer travel on the listing itself — they are the
    // parts that name a door, so they live in the gated address table and arrive
    // via _loadExactAddress() below. Seeded from the listing anyway for local
    // and mock listings, which still carry them inline.
    _flatFloorController = TextEditingController(text: l.flatFloor ?? '');
    _houseNoController = TextEditingController(text: l.houseNo ?? '');
    _streetController = TextEditingController(text: l.street ?? '');
    _areaController = TextEditingController(text: l.area ?? '');
    _cityController = TextEditingController(text: l.city ?? '');
    _postalCodeController = TextEditingController(text: l.postalCode ?? '');
    _landmarkController = TextEditingController(text: l.landmark ?? '');
    // Seed each rate field with its current value, or a sensible default the
    // host sees only after re-enabling a plan that wasn't offered.
    _hourlyPriceController =
        TextEditingController(text: l.hourlyRate?.toStringAsFixed(0) ?? '150');
    _dailyPriceController =
        TextEditingController(text: l.dailyRate?.toStringAsFixed(0) ?? '1500');
    _monthlyPriceController = TextEditingController(
        text: l.monthlyRate?.toStringAsFixed(0) ?? '35000');

    _propertyType = l.type;
    _selectedPurposes = l.purposeTags.toSet();
    _latitude = l.latitude;
    _longitude = l.longitude;
    _maxGuests = l.maxGuests;
    _bedrooms = l.bedrooms;
    _beds = l.beds;
    _bathrooms = l.bathrooms;
    _selectedAmenities = l.amenityNames.toSet();

    _hourlyEnabled = l.hourlyRate != null;
    _dailyEnabled = l.dailyRate != null;
    _monthlyEnabled = l.monthlyRate != null;

    final limits = l.bookingLimits;
    String limitText(int? v) => v?.toString() ?? '';
    _minHoursController =
        TextEditingController(text: limitText(limits.minHours));
    _maxHoursController =
        TextEditingController(text: limitText(limits.maxHours));
    _minNightsController =
        TextEditingController(text: limitText(limits.minNights));
    _maxNightsController =
        TextEditingController(text: limitText(limits.maxNights));
    _minMonthsController =
        TextEditingController(text: limitText(limits.minMonths));
    _maxMonthsController =
        TextEditingController(text: limitText(limits.maxMonths));

    final rules = l.houseRules;
    _checkInTimeController =
        TextEditingController(text: rules.checkInTime ?? '');
    _checkOutTimeController =
        TextEditingController(text: rules.checkOutTime ?? '');
    _quietHoursController = TextEditingController(text: rules.quietHours ?? '');
    _additionalRulesController =
        TextEditingController(text: rules.additionalRules ?? '');
    _smokingAllowed = rules.smokingAllowed;
    _petsAllowed = rules.petsAllowed;
    _partiesAllowed = rules.partiesAllowed;

    _directionsController = TextEditingController();
    _wifiNameController = TextEditingController();
    _wifiPasswordController = TextEditingController();
    _accessCodeController = TextEditingController();
    // Check-in details live in a separate host-only table; load them async.
    _loadCheckInDetails();
    _loadExactAddress();

    _originalImageUrls = List<String>.from(l.imageUrls);
    _images = l.imageUrls
        .map((url) => SelectedImage(
              uploadedUrl: url,
              storagePath: _storagePathFromUrl(url),
            ))
        .toList();

    // Mark the form dirty on any text edit — including the check-in/WiFi/rules
    // fields that have no onChanged handler. Added after seeding so the initial
    // values don't count as edits.
    for (final c in [
      _titleController,
      _descriptionController,
      _flatFloorController,
      _houseNoController,
      _streetController,
      _areaController,
      _cityController,
      _postalCodeController,
      _landmarkController,
      _hourlyPriceController,
      _dailyPriceController,
      _monthlyPriceController,
      _minHoursController,
      _maxHoursController,
      _minNightsController,
      _maxNightsController,
      _minMonthsController,
      _maxMonthsController,
      _checkInTimeController,
      _checkOutTimeController,
      _quietHoursController,
      _additionalRulesController,
      _directionsController,
      _wifiNameController,
      _wifiPasswordController,
      _accessCodeController,
    ]) {
      c.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
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

  /// Derives the storage path ("{listingId}/{file}") from a public image URL,
  /// needed to delete the file when a host removes a photo.
  String? _storagePathFromUrl(String url) {
    const marker = '/${StorageBuckets.listingImages}/';
    final i = url.indexOf(marker);
    if (i == -1) return null;
    return url.substring(i + marker.length);
  }

  /// Pulls the host's own street address out of the gated table. `public.listings`
  /// only carries the area-level form, so without this the edit form would show a
  /// host their own address blanked out and quietly save the blanks back.
  ///
  /// A null answer means the server declined; leave whatever is on screen alone.
  Future<void> _loadExactAddress() async {
    final exact =
        await widget.repository.fetchListingExactAddress(widget.listing.id);
    if (exact == null || !mounted) return;

    // Seeding, not a user edit — don't let it flip the dirty flag.
    _trackChanges = false;
    setState(() {
      if (exact.houseNo != null) _houseNoController.text = exact.houseNo!;
      if (exact.flatFloor != null) _flatFloorController.text = exact.flatFloor!;
      if (exact.street != null) {
        _streetController.text = exact.street!;
      } else if (_streetController.text.isEmpty &&
          _houseNoController.text.isEmpty &&
          exact.address != null) {
        // Rows written before the structured columns existed have only the
        // composed line. Put it in the road field so the host can see and split
        // it rather than being shown an empty form.
        _streetController.text = exact.address!;
      }
    });
    _trackChanges = true;
  }

  Future<void> _loadCheckInDetails() async {
    final access =
        await widget.repository.fetchCheckInDetails(widget.listing.id);
    if (access == null || !mounted) return;
    // Seeding, not a user edit — don't let it flip the dirty flag.
    _trackChanges = false;
    setState(() {
      _directionsController.text = access.directions ?? '';
      _wifiNameController.text = access.wifiName ?? '';
      _wifiPasswordController.text = access.wifiPassword ?? '';
      _accessCodeController.text = access.accessCode ?? '';
    });
    _trackChanges = true;
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _pricingError() => validatePlanRates(
        hourlyEnabled: _hourlyEnabled,
        dailyEnabled: _dailyEnabled,
        monthlyEnabled: _monthlyEnabled,
        hourlyText: _hourlyPriceController.text,
        dailyText: _dailyPriceController.text,
        monthlyText: _monthlyPriceController.text,
      );

  String? _formError() {
    if (_titleController.text.trim().isEmpty) return 'Add a listing title.';
    if (_streetController.text.trim().isEmpty) return 'Add the road / street.';
    if (_areaController.text.trim().isEmpty) return 'Add the area / locality.';
    if (_cityController.text.trim().isEmpty) return 'Add the city.';
    if (_images.isEmpty) return 'Add at least one photo.';
    return _pricingError();
  }

  Future<void> _save() async {
    final error = _formError();
    if (error != null) {
      ModernBanner.showWarning(context, error);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Upload any newly added local images, preserving order; keep the URLs
      // of images that were already uploaded.
      final uploadService = ImageUploadService.instance;
      final finalUrls = <String>[];
      for (var i = 0; i < _images.length; i++) {
        final img = _images[i];
        if (img.uploadedUrl != null) {
          finalUrls.add(img.uploadedUrl!);
          continue;
        }
        if (img.localPath == null) continue;

        setState(() =>
            _images[i] = img.copyWith(isUploading: true, uploadProgress: 0));
        final result = await uploadService.uploadListingImage(
          image: XFile(img.localPath!),
          listingId: widget.listing.id,
          onProgress: (p) {
            if (mounted) {
              setState(
                  () => _images[i] = _images[i].copyWith(uploadProgress: p));
            }
          },
        );
        if (result.success && result.publicUrl != null) {
          setState(() => _images[i] = _images[i].copyWith(
                isUploading: false,
                uploadedUrl: result.publicUrl,
                storagePath: result.storagePath,
              ));
          finalUrls.add(result.publicUrl!);
        } else {
          setState(() => _images[i] = _images[i].copyWith(
                isUploading: false,
                error: result.errorMessage ?? 'Upload failed',
              ));
          throw Exception(
              'Failed to upload image ${i + 1}: ${result.errorMessage}');
        }
      }

      final hourlyRate =
          _hourlyEnabled ? double.parse(_hourlyPriceController.text) : null;
      final dailyRate =
          _dailyEnabled ? double.parse(_dailyPriceController.text) : null;
      final monthlyRate =
          _monthlyEnabled ? double.parse(_monthlyPriceController.text) : null;

      final desc = _descriptionController.text.trim();
      final l = widget.listing;

      // Build the updated listing explicitly (not copyWith) so that clearing
      // the description and disabling plans both persist as null.
      final updated = Listing(
        id: l.id,
        ownerName: l.ownerName,
        hostId: l.hostId,
        hostAvatarUrl: l.hostAvatarUrl,
        title: _titleController.text.trim(),
        description: desc.isEmpty ? null : desc,
        address: Listing.composeAddress(
          houseNo: _houseNoController.text,
          flatFloor: _flatFloorController.text,
          street: _streetController.text,
          area: _areaController.text,
          city: _cityController.text,
          postalCode: _postalCodeController.text,
        ),
        city: _cityController.text.trim(),
        flatFloor: _nullIfEmpty(_flatFloorController.text),
        houseNo: _nullIfEmpty(_houseNoController.text),
        street: _nullIfEmpty(_streetController.text),
        area: _nullIfEmpty(_areaController.text),
        postalCode: _nullIfEmpty(_postalCodeController.text),
        landmark: _nullIfEmpty(_landmarkController.text),
        country: l.country,
        type: _propertyType,
        purposeTags: _selectedPurposes.toList(),
        latitude: _latitude,
        longitude: _longitude,
        hourlyRate: hourlyRate,
        dailyRate: dailyRate,
        monthlyRate: monthlyRate,
        imageUrls: finalUrls,
        maxGuests: _maxGuests,
        bedrooms: _bedrooms,
        beds: _beds,
        bathrooms: _bathrooms,
        facilities: FacilityCatalog.ownerSelectable
            .where((f) => _selectedAmenities.contains(f.name))
            .toList(),
        rating: l.rating,
        reviewCount: l.reviewCount,
        isSuperhost: l.isSuperhost,
        currency: l.currency,
        available: l.available,
        bookingLimits: BookingLimits(
          minHours: hourlyRate != null
              ? int.tryParse(_minHoursController.text)
              : null,
          maxHours: hourlyRate != null
              ? int.tryParse(_maxHoursController.text)
              : null,
          minNights: dailyRate != null
              ? int.tryParse(_minNightsController.text)
              : null,
          maxNights: dailyRate != null
              ? int.tryParse(_maxNightsController.text)
              : null,
          minMonths: monthlyRate != null
              ? int.tryParse(_minMonthsController.text)
              : null,
          maxMonths: monthlyRate != null
              ? int.tryParse(_maxMonthsController.text)
              : null,
        ),
        houseRules: HouseRules(
          checkInTime: _nullIfEmpty(_checkInTimeController.text),
          checkOutTime: _nullIfEmpty(_checkOutTimeController.text),
          smokingAllowed: _smokingAllowed,
          petsAllowed: _petsAllowed,
          partiesAllowed: _partiesAllowed,
          quietHours: _nullIfEmpty(_quietHoursController.text),
          additionalRules: _nullIfEmpty(_additionalRulesController.text),
        ),
        checkInDetails: CheckInDetails(
          directions: _nullIfEmpty(_directionsController.text),
          wifiName: _nullIfEmpty(_wifiNameController.text),
          wifiPassword: _nullIfEmpty(_wifiPasswordController.text),
          accessCode: _nullIfEmpty(_accessCodeController.text),
        ),
      );

      await widget.repository.updateListing(updated);

      // Delete photos the host removed (originally uploaded, now gone).
      final removed =
          _originalImageUrls.where((u) => !finalUrls.contains(u)).toList();
      for (final url in removed) {
        final path = _storagePathFromUrl(url);
        if (path != null) {
          await uploadService.deleteListingImage(path);
        }
      }

      if (mounted) {
        // Changes are persisted — allow leaving without the discard prompt,
        // and ignore the _isSaving teardown setState in `finally`.
        _trackChanges = false;
        _dirty = false;
        Navigator.pop(context);
        ModernBanner.showSuccess(context, 'Listing updated');
      }
    } catch (e) {
      if (mounted) {
        ModernBanner.showError(context, 'Failed to update listing: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pricingError = _pricingError();

    return PopScope(
      // Intercept every back attempt; we decide whether to pop after checking
      // for unsaved changes.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (!_dirty || await _confirmDiscard()) {
          navigator.pop();
        }
      },
      child: _buildScaffold(theme, pricingError),
    );
  }

  /// Confirms leaving with unsaved edits. Returns true to discard and leave.
  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          "You've made changes that haven't been saved. If you leave now, "
          'they will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Widget _buildScaffold(ThemeData theme, String? pricingError) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit listing')),
      body: ResponsiveCenter(
        maxWidth: 760,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- Basics ----------
              _sectionTitle(theme, 'Basics'),
              AppTextField(
                controller: _titleController,
                label: 'Listing title',
                hint: 'e.g., Cozy room in the heart of Gulshan',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _descriptionController,
                label: 'Description (optional)',
                hint: 'Describe the unique features of your space...',
                maxLines: 5,
                onChanged: (_) => setState(() {}),
              ),

              _sectionDivider(),

              // ---------- Type ----------
              _sectionTitle(theme, 'Property type'),
              Wrap(
                spacing: 8,
                children: ListingType.values.map((t) {
                  return ChoiceChip(
                    label: Text(t.title),
                    selected: _propertyType == t,
                    onSelected: (_) => setState(() => _propertyType = t),
                  );
                }).toList(),
              ),

              _sectionDivider(),

              // ---------- Purpose ----------
              PurposeSelector(
                selected: _selectedPurposes,
                onChanged: (next) => setState(() {
                  _selectedPurposes
                    ..clear()
                    ..addAll(next);
                }),
              ),

              _sectionDivider(),

              // ---------- Location ----------
              _sectionTitle(theme, 'Location'),
              AppTextField(
                controller: _houseNoController,
                label: 'House / Building no.',
                hint: 'e.g., House 12',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _flatFloorController,
                label: 'Flat / Floor (optional)',
                hint: 'e.g., B-4, 3rd floor',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _streetController,
                label: 'Road / Street',
                hint: 'e.g., Road 27',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _areaController,
                label: 'Area / Locality',
                hint: 'e.g., Banani',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _cityController,
                label: 'City',
                hint: 'e.g., Dhaka',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _postalCodeController,
                label: 'Postal code (optional)',
                hint: 'e.g., 1213',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _landmarkController,
                label: 'Landmark (optional)',
                hint: 'e.g., Near Banani Bridge',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await LocationPicker.show(
                    context,
                    initialLatitude: _latitude,
                    initialLongitude: _longitude,
                  );
                  if (!mounted) return;
                  if (result != null) {
                    setState(() {
                      _latitude = result.latitude;
                      _longitude = result.longitude;
                      // Seed Road/Street from the geocoded address only if empty.
                      if (result.address != null &&
                          result.address!.isNotEmpty &&
                          _streetController.text.trim().isEmpty) {
                        _streetController.text = result.address!;
                      }
                    });
                  }
                },
                icon: const Icon(Icons.map),
                label: const Text('Pick on Map'),
              ),
              const SizedBox(height: 8),
              Text(
                'Location: ${_latitude.toStringAsFixed(4)}, ${_longitude.toStringAsFixed(4)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              _sectionDivider(),

              // ---------- Details ----------
              _sectionTitle(theme, 'Details'),
              _CounterRow(
                label: 'Guests',
                value: _maxGuests,
                min: 1,
                max: 16,
                onChanged: (v) => setState(() => _maxGuests = v),
              ),
              const Divider(),
              _CounterRow(
                label: 'Bedrooms',
                value: _bedrooms,
                min: 1,
                max: 10,
                onChanged: (v) => setState(() => _bedrooms = v),
              ),
              const Divider(),
              _CounterRow(
                label: 'Beds',
                value: _beds,
                min: 1,
                max: 20,
                onChanged: (v) => setState(() => _beds = v),
              ),
              const Divider(),
              _CounterRow(
                label: 'Bathrooms',
                value: _bathrooms,
                min: 1,
                max: 10,
                onChanged: (v) => setState(() => _bathrooms = v),
              ),
              const SizedBox(height: 20),
              Text(
                'Amenities',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
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
                    final selected = _selectedAmenities.contains(facility.name);
                    return FilterChip(
                      selected: selected,
                      label: Text(facility.name),
                      avatar: Icon(facility.icon, size: 18),
                      onSelected: (_) => setState(() {
                        if (selected) {
                          _selectedAmenities.remove(facility.name);
                        } else {
                          _selectedAmenities.add(facility.name);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ],

              _sectionDivider(),

              // ---------- Pricing ----------
              _sectionTitle(theme, 'Pricing'),
              Text(
                'Turn off any plan you don\'t offer — at least one must stay on.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              PlanPriceRow(
                controller: _hourlyPriceController,
                label: 'Hourly rate',
                icon: Icons.schedule,
                hint: '150',
                helperText: 'For short stays (1-12 hours)',
                enabled: _hourlyEnabled,
                onToggled: (v) => setState(() => _hourlyEnabled = v),
                onChanged: () => setState(() {}),
                minController: _minHoursController,
                maxController: _maxHoursController,
                unitLabel: 'hours',
              ),
              const SizedBox(height: 20),
              PlanPriceRow(
                controller: _dailyPriceController,
                label: 'Daily rate (per night)',
                icon: Icons.today,
                hint: '1500',
                helperText: 'For overnight stays',
                enabled: _dailyEnabled,
                onToggled: (v) => setState(() => _dailyEnabled = v),
                onChanged: () => setState(() {}),
                minController: _minNightsController,
                maxController: _maxNightsController,
                unitLabel: 'nights',
              ),
              const SizedBox(height: 20),
              PlanPriceRow(
                controller: _monthlyPriceController,
                label: 'Monthly rate',
                icon: Icons.calendar_month,
                hint: '35000',
                helperText: 'For long-term stays (1+ months)',
                enabled: _monthlyEnabled,
                onToggled: (v) => setState(() => _monthlyEnabled = v),
                onChanged: () => setState(() {}),
                minController: _minMonthsController,
                maxController: _maxMonthsController,
                unitLabel: 'months',
              ),
              if (pricingError != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pricingError,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              _sectionDivider(),

              // ---------- House rules ----------
              _sectionTitle(theme, 'House rules'),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _checkInTimeController,
                      label: 'Check-in time',
                      hint: 'e.g. 2:00 PM',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      controller: _checkOutTimeController,
                      label: 'Check-out time',
                      hint: 'e.g. 11:00 AM',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Smoking allowed'),
                value: _smokingAllowed,
                onChanged: (v) => setState(() => _smokingAllowed = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pets allowed'),
                value: _petsAllowed,
                onChanged: (v) => setState(() => _petsAllowed = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Parties / events allowed'),
                value: _partiesAllowed,
                onChanged: (v) => setState(() => _partiesAllowed = v),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _quietHoursController,
                label: 'Quiet hours (optional)',
                hint: 'e.g. 10:00 PM – 7:00 AM',
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _additionalRulesController,
                label: 'Additional rules (optional)',
                hint: 'Anything else guests should know',
                maxLines: 4,
              ),

              _sectionDivider(),

              // ---------- Check-in & access (private) ----------
              _sectionTitle(theme, 'Check-in & access'),
              Text(
                'Private — shared with a guest only after their booking is '
                'confirmed. Never shown publicly.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _directionsController,
                label: 'Directions (optional)',
                hint: 'Landmarks, floor, which gate to use…',
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _wifiNameController,
                label: 'Wi-Fi network name (optional)',
                hint: 'e.g. Musaafir_5G',
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _wifiPasswordController,
                label: 'Wi-Fi password (optional)',
                hint: 'Shared only with confirmed guests',
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _accessCodeController,
                label: 'Door / access code (optional)',
                hint: 'e.g. 1234# or lockbox code',
              ),

              _sectionDivider(),

              // ---------- Photos ----------
              ImagePickerGrid(
                images: _images,
                onImagesChanged: (imgs) => setState(() => _images = imgs),
                enabled: !_isSaving,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
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
        child: FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save changes'),
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style:
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _sectionDivider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Divider(height: 1),
      );
}

/// Stepper row for an integer value (guests, bedrooms, etc.).
class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyLarge),
          ),
          IconButton.outlined(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton.outlined(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
