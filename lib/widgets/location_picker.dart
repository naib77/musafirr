import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/location_service.dart';

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

class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    this.initialLatitude = 23.8103,
    this.initialLongitude = 90.4125,
  });

  final double initialLatitude;
  final double initialLongitude;

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
  final _searchController = TextEditingController();

  late double _currentLat;
  late double _currentLng;
  String? _currentAddress;
  bool _isLoadingAddress = false;
  bool _isLoadingLocation = false;
  bool _isSearching = false;
  List<_SearchResult> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _currentLat = widget.initialLatitude;
    _currentLng = widget.initialLongitude;
    _fetchAddress();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAddress() async {
    setState(() => _isLoadingAddress = true);
    final address = await _locationService.getAddressFromCoordinates(
      _currentLat,
      _currentLng,
    );
    if (mounted) {
      setState(() {
        _currentAddress = address;
        _isLoadingAddress = false;
      });
    }
  }

  Future<void> _goToMyLocation() async {
    setState(() => _isLoadingLocation = true);

    final position = await _locationService.getCurrentLocation();

    if (mounted) {
      setState(() => _isLoadingLocation = false);
    }

    if (position != null && _controller != null) {
      final latLng = LatLng(position.latitude, position.longitude);
      _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 16),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Could not get your location. Please check permissions.'),
        ),
      );
    }
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().length < 3) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    final locations = await _locationService.searchAddress(query);

    if (mounted) {
      setState(() {
        _isSearching = false;
        _searchResults = locations
            .map((loc) => _SearchResult(
                  title: query,
                  latitude: loc.latitude,
                  longitude: loc.longitude,
                ))
            .toList();
      });
    }
  }

  void _onCameraIdle() {
    _fetchAddress();
  }

  void _onCameraMove(CameraPosition position) {
    _currentLat = position.target.latitude;
    _currentLng = position.target.longitude;
  }

  void _selectSearchResult(_SearchResult result) {
    _searchController.clear();
    setState(() => _searchResults = []);

    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(result.latitude, result.longitude),
        16,
      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Location'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.initialLatitude, widget.initialLongitude),
              zoom: 15,
            ),
            onMapCreated: (controller) => _controller = controller,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Center pin (Uber style)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Icon(
                Icons.location_pin,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),

          // Search bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search address...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchResults = []);
                                  },
                                )
                              : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: _searchAddress,
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          leading: const Icon(Icons.location_on_outlined),
                          title: Text(result.title),
                          subtitle: Text(
                            '${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)}',
                          ),
                          onTap: () => _selectSearchResult(result),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // My location button
          Positioned(
            bottom: 180,
            right: 16,
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

          // Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
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
                    '${_currentLat.toStringAsFixed(6)}, ${_currentLng.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _confirmLocation,
                    child: const Text('Confirm Location'),
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

class _SearchResult {
  const _SearchResult({
    required this.title,
    required this.latitude,
    required this.longitude,
  });

  final String title;
  final double latitude;
  final double longitude;
}
