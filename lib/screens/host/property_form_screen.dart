import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/utils/responsive.dart';
import '../../models/hotel_details.dart';
import '../../models/listing.dart';
import '../../models/property.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/host/hotel_details_fields.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/modern_banner.dart';
import 'property_dashboard_screen.dart';

/// The hotel itself, entered once (plan §8 step 1): name, location, check-in
/// times and the hotel facts every room type shares. Room types are added
/// from [PropertyDashboardScreen] afterwards.
///
/// One form for create and edit. On edit, the database pushes the shared
/// fields down to every room type in the same transaction, so a moved pin or
/// a new check-in time reaches all of them at once.
class PropertyFormScreen extends StatefulWidget {
  const PropertyFormScreen({
    super.key,
    required this.repository,
    required this.authState,
    this.property,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;

  /// Null to create a hotel.
  final Property? property;

  @override
  State<PropertyFormScreen> createState() => _PropertyFormScreenState();
}

class _PropertyFormScreenState extends State<PropertyFormScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _houseNo = TextEditingController();
  final _street = TextEditingController();
  final _area = TextEditingController();
  final _city = TextEditingController(text: 'Dhaka');
  final _postalCode = TextEditingController();
  final _landmark = TextEditingController();
  final _checkIn = TextEditingController(text: '2:00 PM');
  final _checkOut = TextEditingController(text: '12:00 PM');
  HotelDetails _details = const HotelDetails();

  // Same default as the listing wizard, and the same rule: it is not a
  // location until the host sets the pin.
  double _latitude = 23.7806;
  double _longitude = 90.4070;
  bool _pinConfirmed = false;
  bool _saving = false;
  bool _loadingAddress = false;

  bool get _isEdit => widget.property != null;

  @override
  void initState() {
    super.initState();
    final p = widget.property;
    if (p == null) return;
    _name.text = p.name;
    _description.text = p.description ?? '';
    _area.text = p.area ?? '';
    _city.text = p.city ?? '';
    _postalCode.text = p.postalCode ?? '';
    _landmark.text = p.landmark ?? '';
    _checkIn.text = p.checkInTime ?? '';
    _checkOut.text = p.checkOutTime ?? '';
    _details = p.hotelDetails;
    _latitude = p.latitude ?? _latitude;
    _longitude = p.longitude ?? _longitude;
    _pinConfirmed = p.latitude != null;
    _loadAddress(p.id);
  }

  /// The door-level line and the precise pin. The public row holds only the
  /// snapped point, so without this an edit would save the snapped one back
  /// over the precise one.
  Future<void> _loadAddress(String id) async {
    setState(() => _loadingAddress = true);
    try {
      final a = await widget.repository.fetchPropertyAddress(id);
      if (!mounted || a == null) return;
      setState(() {
        _houseNo.text = a.houseNo ?? '';
        _street.text = a.street ?? '';
        if (a.latitude != null && a.longitude != null) {
          _latitude = a.latitude!;
          _longitude = a.longitude!;
        }
      });
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _houseNo,
      _street,
      _area,
      _city,
      _postalCode,
      _landmark,
      _checkIn,
      _checkOut,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _error() {
    if (_name.text.trim().isEmpty) return 'Add the hotel\'s name.';
    if (_street.text.trim().isEmpty) return 'Add the road / street.';
    if (_area.text.trim().isEmpty) return 'Add the area / locality.';
    if (_city.text.trim().isEmpty) return 'Add the city.';
    if (!_pinConfirmed) return 'Set the hotel\'s location on the map.';
    return null;
  }

  static String? _blankToNull(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _save() async {
    if (_error() != null || _saving) return;
    final ownerId =
        widget.property?.ownerId ?? widget.authState.currentUser?.id;
    if (ownerId == null) return;
    setState(() => _saving = true);

    final property = Property(
      id: widget.property?.id ?? '',
      ownerId: ownerId,
      name: _name.text.trim(),
      description: _blankToNull(_description.text),
      area: _blankToNull(_area.text),
      city: _blankToNull(_city.text),
      country: 'Bangladesh',
      postalCode: _blankToNull(_postalCode.text),
      landmark: _blankToNull(_landmark.text),
      // Sent precise; trg_property_normalise snaps the public copy. The
      // precise point goes to property_addresses below.
      latitude: _latitude,
      longitude: _longitude,
      checkInTime: _blankToNull(_checkIn.text),
      checkOutTime: _blankToNull(_checkOut.text),
      hotelDetails: _details,
      imageUrls: widget.property?.imageUrls ?? const [],
    );
    final address = PropertyAddress(
      houseNo: _blankToNull(_houseNo.text),
      street: _blankToNull(_street.text),
      exactAddress: Listing.composeAddress(
        houseNo: _houseNo.text,
        street: _street.text,
        area: _area.text,
        city: _city.text,
        postalCode: _postalCode.text,
      ),
      latitude: _latitude,
      longitude: _longitude,
    );

    try {
      if (_isEdit) {
        await widget.repository.updateProperty(property, address);
        if (!mounted) return;
        Navigator.pop(context, true);
        ModernBanner.showSuccess(context, 'Hotel saved');
      } else {
        final id = await widget.repository.createProperty(property, address);
        final created = await widget.repository.fetchProperty(id);
        if (!mounted) return;
        // Straight on to the room types: a hotel with none is invisible to
        // guests (153's select policy), so stopping here would look broken.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PropertyDashboardScreen(
              repository: widget.repository,
              authState: widget.authState,
              property: created ?? property,
              promptFirstRoomType: true,
            ),
          ),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ModernBanner.showError(context, propertyRefusalMessage(e.hint));
      }
    } catch (e) {
      if (mounted) ModernBanner.showError(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickOnMap() async {
    final result = await LocationPicker.show(
      context,
      initialLatitude: _latitude,
      initialLongitude: _longitude,
    );
    if (!mounted || result == null) return;
    setState(() {
      _latitude = result.latitude;
      _longitude = result.longitude;
      _pinConfirmed = true;
      final a = result.address;
      if (a != null && a.isNotEmpty && _street.text.trim().isEmpty) {
        _street.text = a;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error();
    void touch(String _) => setState(() {});

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 12),
          child: Text(
            title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit hotel' : 'Your hotel')),
      body: ResponsiveCenter(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!_isEdit)
              Text(
                'Start with the hotel itself. Next you will add its room '
                'types — Deluxe, Super Deluxe, Sea Front — each with its own '
                'rooms and price.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            section('Basics'),
            AppTextField(
              controller: _name,
              label: 'Hotel name',
              hint: 'e.g., Hotel Sea Crown',
              onChanged: touch,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _description,
              label: 'About the hotel (optional)',
              hint: 'What guests should know about the hotel as a whole',
              maxLines: 4,
            ),
            section('Location'),
            Text(
              'The exact address is shared with guests only after they '
              'book.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_loadingAddress) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            AppTextField(
              controller: _houseNo,
              label: 'House / Building no. (optional)',
              hint: 'e.g., Plot 15',
              onChanged: touch,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _street,
              label: 'Road / Street',
              hint: 'e.g., Marine Drive',
              onChanged: touch,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _area,
              label: 'Area / Locality',
              hint: 'e.g., Kolatoli',
              onChanged: touch,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _city,
              label: 'City',
              hint: 'e.g., Cox\'s Bazar',
              onChanged: touch,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _postalCode,
              label: 'Postal code (optional)',
              hint: 'e.g., 4700',
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _landmark,
              label: 'Landmark (optional)',
              hint: 'e.g., Near Sugandha Point',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: _pinConfirmed
                  ? OutlinedButton.icon(
                      onPressed: _pickOnMap,
                      icon: const Icon(Icons.map),
                      label: const Text('Change location on map'),
                    )
                  : FilledButton.icon(
                      onPressed: _pickOnMap,
                      icon: const Icon(Icons.map),
                      label: const Text('Set location on map'),
                    ),
            ),
            section('Check-in'),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _checkIn,
                    label: 'Check-in time',
                    hint: 'e.g. 2:00 PM',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _checkOut,
                    label: 'Check-out time',
                    hint: 'e.g. 12:00 PM',
                  ),
                ),
              ],
            ),
            section('About the hotel'),
            HotelDetailsFields(
              details: _details,
              onChanged: (v) => setState(() => _details = v),
            ),
            const SizedBox(height: 24),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: error == null && !_saving ? _save : null,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Save hotel' : 'Next: add room types'),
            ),
          ],
        ),
      ),
    );
  }
}
