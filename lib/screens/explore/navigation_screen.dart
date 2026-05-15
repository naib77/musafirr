import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/listing.dart';
import '../../services/directions_service.dart';
import '../../services/location_service.dart';

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
  String? _error;
  String _travelMode = 'driving';

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
          _error = 'Could not get your location. Please enable location services.';
          _isLoading = false;
        });
        return;
      }

      _currentLocation = LatLng(position.latitude, position.longitude);

      // On web, we can't call Directions API directly due to CORS
      // So we just show both locations and let user open Google Maps for navigation
      if (kIsWeb) {
        setState(() {
          _isLoading = false;
        });

        // Fit map to show both markers
        _fitMapToBothLocations();
        return;
      }

      // On mobile, get directions
      final directions = await DirectionsService.getDirections(
        origin: _currentLocation!,
        destination: _destinationLocation,
        mode: _travelMode,
      );

      if (directions == null) {
        setState(() {
          _error = 'Could not find directions. Please try again.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _directions = directions;
        _isLoading = false;
      });

      // Fit map to show entire route
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(directions.bounds, 80),
      );
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
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
    final destination = '${_destinationLocation.latitude},${_destinationLocation.longitude}';

    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '${origin.isNotEmpty ? '&origin=$origin' : ''}'
      '&destination=$destination'
      '&travelmode=$_travelMode',
    );

    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open Google Maps: $e')),
        );
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
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Directions to ${widget.listing.title}'),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _destinationLocation,
              zoom: 14,
            ),
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) {
              _mapController = controller;
              if (_directions != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngBounds(_directions!.bounds, 80),
                );
              }
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
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
          if ((_directions != null || (kIsWeb && _currentLocation != null)) && !_isLoading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
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
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'driving',
                              icon: Icon(Icons.directions_car),
                              label: Text('Drive'),
                            ),
                            ButtonSegment(
                              value: 'walking',
                              icon: Icon(Icons.directions_walk),
                              label: Text('Walk'),
                            ),
                            ButtonSegment(
                              value: 'bicycling',
                              icon: Icon(Icons.directions_bike),
                              label: Text('Bike'),
                            ),
                            ButtonSegment(
                              value: 'transit',
                              icon: Icon(Icons.directions_transit),
                              label: Text('Transit'),
                            ),
                          ],
                          selected: {_travelMode},
                          onSelectionChanged: (selected) {
                            _changeTravelMode(selected.first);
                          },
                        ),
                        const SizedBox(height: 16),

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
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      widget.listing.address,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Open in Google Maps button (for web or as an option)
                        if (kIsWeb) ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _openInGoogleMaps,
                            icon: const Icon(Icons.navigation),
                            label: const Text('Start Navigation in Google Maps'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                        ],
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
