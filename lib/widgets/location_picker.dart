import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';
import 'map_place_search_bar.dart';
import 'modern_banner.dart';
import 'web_deferred_mount.dart';

class LocationPickerResult {
  const LocationPickerResult({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final double latitude;
  final double longitude;
  final String? address;
}

/// What the picker needs a map to do: open at [initialTarget] and report where
/// the camera is. Injected as a builder so the picker can be pumped in a test
/// without a platform view.
class LocationPickerMapSpec {
  const LocationPickerMapSpec({
    required this.initialTarget,
    required this.onMapCreated,
    required this.onCameraMove,
    required this.onCameraIdle,
  });

  final LatLng initialTarget;
  final void Function(GoogleMapController controller) onMapCreated;
  final void Function(CameraPosition position) onCameraMove;
  final VoidCallback onCameraIdle;
}

typedef LocationPickerMapBuilder = Widget Function(LocationPickerMapSpec spec);

/// Uber-style location picker: the pin stays in the middle, the host moves the
/// map under it, and the search bar jumps the map to a place by name.
class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    this.initialLatitude = 23.8103,
    this.initialLongitude = 90.4125,
    this.mapBuilder,
    this.suggest,
    this.locate,
    this.addressOf,
  });

  final double initialLatitude;
  final double initialLongitude;

  /// Test seams. Production uses a real [GoogleMap], [PlacesService] and
  /// [GeocodingService].
  final LocationPickerMapBuilder? mapBuilder;
  final PlaceSuggestFn? suggest;
  final PlaceLocateFn? locate;
  final Future<String?> Function(double latitude, double longitude)? addressOf;

  static const Key confirmKey = ValueKey('location-picker-confirm');
  static const Key coordinatesKey = ValueKey('location-picker-coordinates');

  static Future<LocationPickerResult?> show(
    BuildContext context, {
    double? initialLatitude,
    double? initialLongitude,
  }) {
    return Navigator.of(context).push<LocationPickerResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => LocationPicker(
          initialLatitude: initialLatitude ?? 23.8103,
          initialLongitude: initialLongitude ?? 90.4125,
        ),
      ),
    );
  }

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  GoogleMapController? _controller;
  final _locationService = LocationService();
  final _geocoding = GeocodingService();

  late double _currentLat;
  late double _currentLng;
  String? _currentAddress;
  bool _isLoadingAddress = false;
  bool _isLoadingLocation = false;
  bool _mapCreated = false;

  @override
  void initState() {
    super.initState();
    _currentLat = widget.initialLatitude;
    _currentLng = widget.initialLongitude;
    _fetchAddress();
  }

  @override
  void dispose() {
    // Only dispose controller if map was fully created (fixes web bug)
    if (_mapCreated && _controller != null) {
      _controller!.dispose();
    }
    super.dispose();
  }

  Future<String?> _lookupAddress(double lat, double lng) =>
      (widget.addressOf ?? _geocoding.reverse)(lat, lng);

  /// Only the newest lookup may write the address — panning the map fires one
  /// per stop, and a slow early answer must not land on a later position.
  int _addressRequest = 0;

  Future<void> _fetchAddress() async {
    final id = ++_addressRequest;
    setState(() => _isLoadingAddress = true);
    final address = await _lookupAddress(_currentLat, _currentLng);
    if (!mounted || id != _addressRequest) return;
    setState(() {
      _currentAddress = address;
      _isLoadingAddress = false;
    });
  }

  Future<void> _goToMyLocation() async {
    setState(() => _isLoadingLocation = true);

    final position = await _locationService.getCurrentLocation();

    if (mounted) {
      setState(() => _isLoadingLocation = false);
    }

    if (position != null) {
      _moveTo(position.latitude, position.longitude);
    } else if (mounted) {
      ModernBanner.showError(
          context, 'Could not get your location. Please check permissions.');
    }
  }

  /// Moves both the camera and the picked coordinates. The camera callbacks
  /// would eventually report the same target, but the readout and the Confirm
  /// button must not wait on an animation — and on a map that never reports
  /// (no camera events fired) they would never update at all.
  void _moveTo(double lat, double lng, {String? address}) {
    setState(() {
      _currentLat = lat;
      _currentLng = lng;
      _currentAddress = address;
      if (address != null) {
        // A name we already know beats anything still in flight.
        _addressRequest++;
        _isLoadingAddress = false;
      }
    });
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
    );
    if (address == null) _fetchAddress();
  }

  void _onCameraIdle() {
    _fetchAddress();
  }

  void _onCameraMove(CameraPosition position) {
    _currentLat = position.target.latitude;
    _currentLng = position.target.longitude;
  }

  void _onPlacePicked(PlaceLocation place) {
    // A searched place already knows its own name — no need to reverse-geocode
    // the coordinates we just got from Google.
    _moveTo(
      place.latitude,
      place.longitude,
      address: place.label?.isNotEmpty == true
          ? '${place.name}, ${place.label}'
          : place.name,
    );
  }

  void _confirmLocation() {
    Navigator.of(context).pop(
      LocationPickerResult(
        latitude: _currentLat,
        longitude: _currentLng,
        address: _currentAddress,
      ),
    );
  }

  Widget _buildMap() {
    final spec = LocationPickerMapSpec(
      initialTarget: LatLng(widget.initialLatitude, widget.initialLongitude),
      onMapCreated: (controller) {
        _controller = controller;
        _mapCreated = true;
      },
      onCameraMove: _onCameraMove,
      onCameraIdle: _onCameraIdle,
    );

    if (widget.mapBuilder != null) return widget.mapBuilder!(spec);

    return WebDeferredMount(
      builder: (context) => GoogleMap(
        initialCameraPosition: CameraPosition(
          target: spec.initialTarget,
          zoom: 15,
        ),
        onMapCreated: spec.onMapCreated,
        onCameraMove: spec.onCameraMove,
        onCameraIdle: spec.onCameraIdle,
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Every control here floats over the map, and on web a Google map is a
      // real DOM element that wins the browser's hit-test against anything
      // Flutter paints on top of it. Without a PointerInterceptor around each
      // one, taps land on the map instead: the host could pan the map but never
      // type in the search box, press Confirm, or even go back.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: PointerInterceptor(
          child: AppBar(
            title: const Text('Pick Location'),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),

          // Center pin (Uber style). Deliberately NOT intercepted — it sits in
          // the middle of the map and must not swallow pans.
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: IgnorePointer(
                child: Icon(
                  Icons.location_pin,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),

          // Search bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 16,
            right: 16,
            child: PointerInterceptor(
              child: MapPlaceSearchBar(
                onPlacePicked: _onPlacePicked,
                suggest: widget.suggest,
                locate: widget.locate,
              ),
            ),
          ),

          // My location button
          Positioned(
            bottom: 180,
            right: 16,
            child: PointerInterceptor(
              child: FloatingActionButton.small(
                heroTag: 'myLocationPicker',
                onPressed: _isLoadingLocation ? null : _goToMyLocation,
                child: _isLoadingLocation
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
            ),
          ),

          // Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: PointerInterceptor(
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  20 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.location_pin,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selected Location',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 2),
                              if (_isLoadingAddress)
                                const Text('Loading address...')
                              else
                                Text(
                                  _currentAddress ??
                                      'Move map to select location',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      key: LocationPicker.coordinatesKey,
                      '${_currentLat.toStringAsFixed(6)}, ${_currentLng.toStringAsFixed(6)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: LocationPicker.confirmKey,
                      onPressed: _confirmLocation,
                      child: const Text('Confirm Location'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
