import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/utils/external_launcher.dart';

import '../../core/privacy/listing_location.dart';
import '../../core/theme/app_colors.dart';
import '../../models/listing.dart';
import '../../services/directions_service.dart';
import '../../services/location_service.dart';
import '../../widgets/map_focus_button.dart';
import '../../widgets/modern_banner.dart';
import '../../widgets/web_deferred_mount.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.listing,
    required this.location,
  });

  final Listing listing;

  /// Where to route to, and how much of the address may be shown. Required
  /// rather than derived from [listing] so this screen cannot leak an exact
  /// address just because a future caller forgot to check: it navigates to
  /// whatever point the gate handed it, and prints whatever label came with it.
  final ListingLocation location;

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

  /// A recenter tap is taking a fresh GPS fix. Shown on the button itself so a
  /// slow fix doesn't read as a dead control.
  bool _recentering = false;

  // The bottom info panel overlays the map, so the map viewport must be
  // padded by the panel's height — otherwise camera fits center the route on
  // the full canvas and the destination ends up hidden behind the panel.
  // Measured after layout because the panel's height varies with content.
  final GlobalKey _panelKey = GlobalKey();
  double _mapBottomPadding = 0;

  LatLng get _destinationLocation => LatLng(
        widget.location.latitude,
        widget.location.longitude,
      );

  Set<Marker> get _markers {
    final markers = <Marker>{
      // Destination marker
      Marker(
        markerId: const MarkerId('destination'),
        position: _destinationLocation,
        infoWindow: InfoWindow(
          title: widget.listing.title,
          snippet: widget.location.label,
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
        if (!mounted) return;
        setState(() {
          _error = kIsWeb
              ? 'Could not get your location. Allow location access for this '
                  'site in your browser and retry, or open Google Maps below.'
              : 'Could not get your location. Please enable location services.';
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
      if (!mounted) return;
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

    final update = framePoints(
      [_currentLocation!, _destinationLocation],
      padding: 80,
    );
    if (update != null) _mapController?.animateCamera(update);
  }

  /// The Uber/Pathao recenter: take a *fresh* GPS fix and drop the camera on it
  /// at street zoom. Fresh rather than the fix from when the screen opened,
  /// because by the time someone reaches for this button they're usually
  /// already on their way.
  Future<void> _recenterOnMe() async {
    if (_recentering) return;
    setState(() => _recentering = true);

    final position = await _locationService.getCurrentLocation();

    if (!mounted) return;
    setState(() {
      _recentering = false;
      if (position != null) {
        // Moves the origin pin too, not just the camera.
        _currentLocation = LatLng(position.latitude, position.longitude);
      }
    });

    if (position == null) {
      ModernBanner.showError(
        context,
        'Could not get your location. Please check permissions.',
      );
      return;
    }

    await focusCamera(
      context,
      _mapController,
      CameraUpdate.newLatLngZoom(_currentLocation!, 16.5),
    );
  }

  /// Frames the destination on its own — the "where am I actually going" tap,
  /// for when the route overview is too wide to make out the address.
  Future<void> _focusDestination() => focusCamera(
        context,
        _mapController,
        CameraUpdate.newLatLngZoom(_destinationLocation, 16.5),
      );

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

  /// The stack of focus controls, or nothing when the info panel has left too
  /// little map above it to put them on — better absent than floating over the
  /// panel and the app bar on a short window.
  Widget _focusControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final controls = <Widget>[
          MapFocusButton(
            icon: Icons.place_rounded,
            label: 'Focus on ${widget.listing.title}',
            onPressed: _focusDestination,
          ),
          MapFocusButton(
            icon: Icons.zoom_out_map_rounded,
            label: _directions != null
                ? 'Show the whole route'
                : 'Show both locations',
            onPressed: _fitCamera,
          ),
          // Primary, and last so it sits closest to the thumb.
          MapFocusButton(
            icon: Icons.my_location_rounded,
            label: 'Center on my location',
            emphasized: true,
            busy: _recentering,
            onPressed: _recenterOnMe,
          ),
        ];

        final diameter = MapFocusButton.diameterOf(context);
        final stackHeight =
            controls.length * diameter + (controls.length - 1) * 8;
        if (constraints.maxHeight - _mapBottomPadding < stackHeight + 24) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: EdgeInsets.only(right: 12, bottom: _mapBottomPadding + 12),
          child: Align(
            alignment: Alignment.bottomRight,
            child: MapFocusControls(children: controls),
          ),
        );
      },
    );
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
              // Ours instead of the SDK's: the native button only exists on
              // Android, sits under the app bar, and doesn't take a fresh fix.
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
            ),
          ),

          // Focus controls, parked above the info panel so they stay reachable
          // whatever height the panel settles at. Hidden while the route loads,
          // where the scrim below would leave them visible but unresponsive.
          //
          // Positioned.fill only so the LayoutBuilder can see how much map
          // there is; Align keeps the controls in the corner, and the empty
          // remainder isn't hit-testable, so map gestures pass straight through.
          if (!_isLoading) Positioned.fill(child: _focusControls()),

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

          // Bottom info panel. Shown as soon as loading finishes, with or
          // without a current location: the "Open in Google Maps" button below
          // works from an empty origin (Google resolves the start itself), so
          // gating the whole panel on _currentLocation left a failed location
          // lookup with an error card and no way to get directions at all.
          if (!_isLoading)
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

                        // Hint shown when the in-app route couldn't load —
                        // either the origin is unknown or the route lookup
                        // failed (e.g. Directions API key restricted/disabled).
                        if (_directions == null) ...[
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
                                      widget.location.label,
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
