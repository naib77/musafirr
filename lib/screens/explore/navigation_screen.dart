import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/utils/external_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../models/listing.dart';
import '../../services/directions_service.dart';
import '../../services/location_service.dart';
import '../../widgets/modern_banner.dart';
import '../../widgets/web_deferred_mount.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.listing,
  });

  final Listing listing;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();

  LatLng? _currentLocation;
  DirectionsResult? _directions;
  bool _isLoading = true;
  bool _mapCreated = false;
  String? _error;
  String _travelMode = 'driving';

  // The bottom info panel overlays the map, so the map viewport must be
  // padded by the panel's height — otherwise camera fits center the route on
  // the full canvas and the destination ends up hidden behind the panel.
  // Measured after layout because the panel's height varies with content.
  final GlobalKey _panelKey = GlobalKey();
  double _mapBottomPadding = 0;

  LatLng get _destinationLocation => LatLng(
        widget.listing.latitude,
        widget.listing.longitude,
      );

  Set<Marker> get _markers {
    final markers = <Marker>{
      // Destination marker
      Marker(
        markerId: const MarkerId('destination'),
        position: _destinationLocation,
        infoWindow: InfoWindow(
          title: widget.listing.title,
          snippet: widget.listing.address,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    // Current location marker
    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: _currentLocation!,
          infoWindow: const InfoWindow(title: 'Your Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> get _polylines {
    if (_directions == null) return {};

    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: _directions!.points,
        color: Colors.blue,
        width: 5,
      ),
    };
  }

  @override
  void initState() {
    super.initState();
    _loadDirections();
  }

  Future<void> _loadDirections() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get current location
      final position = await _locationService.getCurrentLocation();

      if (position == null) {
        setState(() {
          _error =
              'Could not get your location. Please enable location services.';
          _isLoading = false;
        });
        return;
      }

      _currentLocation = LatLng(position.latitude, position.longitude);

      // Fetch the in-app route polyline. This is proxied through the
      // google-directions Edge Function (key stays a server secret) and works on
      // web and mobile alike. If it returns null (not configured / no route) we
      // degrade to showing both pins + the "Open in Google Maps" button.
      final directions = await DirectionsService.getDirections(
        origin: _currentLocation!,
        destination: _destinationLocation,
        mode: _travelMode,
      );

      if (!mounted) return;
      setState(() {
        _directions = directions;
        _isLoading = false;
      });

      _fitCamera();
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  /// Fits the camera to whatever we have: the route, both pins, or just the
  /// destination. Safe to call repeatedly (map creation, directions loaded,
  /// panel height measured).
  void _fitCamera() {
    if (_mapController == null) return;
    if (_directions != null) {
      // Fit map to show the entire route.
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(_directions!.bounds, 80),
      );
    } else if (_currentLocation != null) {
      // No in-app route — still useful: show both pins and let the user open
      // the native Google Maps app for turn-by-turn navigation.
      _fitMapToBothLocations();
    } else {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_destinationLocation, 15),
      );
    }
  }

  /// Measures the bottom panel after layout and re-pads/refits the map when
  /// its height changes (panel content differs by state).
  void _measurePanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = _panelKey.currentContext?.size?.height ?? 0;
      if ((height - _mapBottomPadding).abs() > 1) {
        setState(() => _mapBottomPadding = height);
        _fitCamera();
      }
    });
  }

  void _fitMapToBothLocations() {
    if (_currentLocation == null || _mapController == null) return;

    final bounds = LatLngBounds(
      southwest: LatLng(
        _currentLocation!.latitude < _destinationLocation.latitude
            ? _currentLocation!.latitude
            : _destinationLocation.latitude,
        _currentLocation!.longitude < _destinationLocation.longitude
            ? _currentLocation!.longitude
            : _destinationLocation.longitude,
      ),
      northeast: LatLng(
        _currentLocation!.latitude > _destinationLocation.latitude
            ? _currentLocation!.latitude
            : _destinationLocation.latitude,
        _currentLocation!.longitude > _destinationLocation.longitude
            ? _currentLocation!.longitude
            : _destinationLocation.longitude,
      ),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  Future<void> _openInGoogleMaps() async {
    final origin = _currentLocation != null
        ? '${_currentLocation!.latitude},${_currentLocation!.longitude}'
        : '';
    final destination =
        '${_destinationLocation.latitude},${_destinationLocation.longitude}';

    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '${origin.isNotEmpty ? '&origin=$origin' : ''}'
      '&destination=$destination'
      '&travelmode=$_travelMode',
    );

    try {
      final launched = await openExternalUrl(url.toString());
      if (!launched && mounted) {
        ModernBanner.showError(context, 'Could not open Google Maps');
      }
    } catch (e) {
      if (mounted) {
        ModernBanner.showError(context, 'Could not open Google Maps: $e');
      }
    }
  }

  void _changeTravelMode(String mode) {
    if (mode != _travelMode) {
      setState(() => _travelMode = mode);
      _loadDirections();
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
    _measurePanel();

    return Scaffold(
      appBar: AppBar(
        title: Text('Directions to ${widget.listing.title}'),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: Stack(
        children: [
          // Map
          WebDeferredMount(
            builder: (context) => GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _destinationLocation,
                zoom: 14,
              ),
              markers: _markers,
              polylines: _polylines,
              // Keep camera fits/centering within the area not covered by the
              // bottom info panel (ignored on web, where the panel is smaller).
              padding: EdgeInsets.only(bottom: _mapBottomPadding),
              onMapCreated: (controller) {
                _mapController = controller;
                _mapCreated = true;
                _fitCamera();
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Getting directions...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Error message
          if (_error != null && !_isLoading)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loadDirections,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom info panel
          if (_currentLocation != null && !_isLoading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                key: _panelKey,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Handle
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Distance and duration (only on mobile with directions)
                        if (_directions != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _InfoChip(
                                icon: Icons.straighten,
                                label: 'Distance',
                                value: _directions!.distance,
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: theme.colorScheme.outlineVariant,
                              ),
                              _InfoChip(
                                icon: Icons.access_time,
                                label: 'Duration',
                                value: _directions!.duration,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Travel mode selector
                        _TravelModeSelector(
                          selected: _travelMode,
                          onChanged: _changeTravelMode,
                        ),
                        const SizedBox(height: 16),

                        // Hint shown when the in-app route couldn't load
                        // (e.g. Directions API key restricted/disabled).
                        if (!kIsWeb && _directions == null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.amber.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.amber.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded,
                                    size: 18, color: AppColors.amber),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'In-app route preview is unavailable. Open '
                                    'Google Maps below for turn-by-turn directions.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Destination info
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.listing.title,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      widget.listing.address,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Open in Google Maps for true turn-by-turn. Always
                        // available — it's the most reliable path on Android
                        // and the fallback when the in-app route is missing.
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _openInGoogleMaps,
                          icon: const Icon(Icons.navigation),
                          label: Text(
                            _directions != null
                                ? 'Start in Google Maps'
                                : 'Open in Google Maps',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Width-fitting travel-mode selector (replaces SegmentedButton, whose
/// 4 icon+label segments overflow on phone widths). Each mode gets an equal
/// Expanded slot, so labels never clip.
class _TravelModeSelector extends StatelessWidget {
  const _TravelModeSelector({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  static const _modes = <(String, IconData, String)>[
    ('driving', Icons.directions_car_filled_rounded, 'Drive'),
    ('walking', Icons.directions_walk_rounded, 'Walk'),
    ('bicycling', Icons.directions_bike_rounded, 'Bike'),
    ('transit', Icons.directions_transit_rounded, 'Transit'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (value, icon, label) in _modes)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    gradient:
                        value == selected ? AppColors.brandGradient : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: value == selected
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: value == selected
                              ? Colors.white
                              : theme.colorScheme.onSurfaceVariant,
                        ),
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
