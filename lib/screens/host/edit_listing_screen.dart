import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/facility_catalog.dart';
import '../../models/listing.dart';
import '../../models/listing_type.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/image_upload_service.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/image_picker_grid.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/modern_banner.dart';
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
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _hourlyPriceController;
  late final TextEditingController _dailyPriceController;
  late final TextEditingController _monthlyPriceController;

  late ListingType _propertyType;
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

  late List<SelectedImage> _images;
  late List<String> _originalImageUrls;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final l = widget.listing;
    _titleController = TextEditingController(text: l.title);
    _descriptionController = TextEditingController(text: l.description ?? '');
    _addressController = TextEditingController(text: l.address);
    _cityController = TextEditingController(text: l.city ?? '');
    // Seed each rate field with its current value, or a sensible default the
    // host sees only after re-enabling a plan that wasn't offered.
    _hourlyPriceController =
        TextEditingController(text: l.hourlyRate?.toStringAsFixed(0) ?? '150');
    _dailyPriceController =
        TextEditingController(text: l.dailyRate?.toStringAsFixed(0) ?? '1500');
    _monthlyPriceController = TextEditingController(
        text: l.monthlyRate?.toStringAsFixed(0) ?? '35000');

    _propertyType = l.type;
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

    _originalImageUrls = List<String>.from(l.imageUrls);
    _images = l.imageUrls
        .map((url) => SelectedImage(
              uploadedUrl: url,
              storagePath: _storagePathFromUrl(url),
            ))
        .toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _hourlyPriceController.dispose();
    _dailyPriceController.dispose();
    _monthlyPriceController.dispose();
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
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        country: l.country,
        type: _propertyType,
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

    return Scaffold(
      appBar: AppBar(title: const Text('Edit listing')),
      body: SingleChildScrollView(
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

            // ---------- Location ----------
            _sectionTitle(theme, 'Location'),
            AppTextField(
              controller: _addressController,
              label: 'Street address',
              hint: 'e.g., Road 27, House 5',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _cityController,
              label: 'City / Area',
              hint: 'e.g., Gulshan, Dhaka',
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
                if (result != null) {
                  setState(() {
                    _latitude = result.latitude;
                    _longitude = result.longitude;
                    if (result.address != null && result.address!.isNotEmpty) {
                      _addressController.text = result.address!;
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: FacilityCatalog.ownerSelectable.map((facility) {
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

            // ---------- Photos ----------
            ImagePickerGrid(
              images: _images,
              onImagesChanged: (imgs) => setState(() => _images = imgs),
              enabled: !_isSaving,
            ),
          ],
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
