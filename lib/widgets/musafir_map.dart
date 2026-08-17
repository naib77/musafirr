import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/privacy/listing_location.dart';
import '../models/listing.dart';
import '../models/listing_type.dart';
import '../models/rental_plan.dart';
import '../services/location_service.dart';
import 'listing_price_map.dart' show mappableListings;
import 'map_focus_button.dart';
import 'modern_banner.dart';
import 'web_deferred_mount.dart';

class MusafirMap extends StatefulWidget {
  const MusafirMap({
    super.key,
    required this.centerLat,
    required this.centerLng,
    this.listings = const [],
    this.onTap,
    this.onCameraMove,
    this.onListingTap,
    this.height = 300,
    this.showMyLocationButton = true,
  });

  final double centerLat;
  final double centerLng;
  final List<Listing> listings;
  final void Function(double lat, double lng)? onTap;
  final void Function(double lat, double lng)? onCameraMove;
  final void Function(Listing listing)? onListingTap;
  final double height;
  final bool showMyLocationButton;

  @override
  State<MusafirMap> createState() => _MusafirMapState();
}

class _MusafirMapState extends State<MusafirMap> {
  GoogleMapController? _controller;
  final _locationService = LocationService();
  bool _isLoadingLocation = false;
  LatLng? _selectedLocation;
  bool _mapCreated = false;

  /// Where a listing's pin goes: the area, never the door.
  static LatLng _pinFor(Listing listing) {
    final at = ListingLocation.approximate(listing);
    return LatLng(at.latitude, at.longitude);
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};

    // Add listing markers
    for (final listing in widget.listings) {
      markers.add(
        Marker(
          markerId: MarkerId(listing.id),
          // Coarsened to the area, like the results map: a browsing guest has
          // no accepted booking for these, so an exact pin would give away the
          // address the listing page withholds.
          position: _pinFor(listing),
          infoWindow: InfoWindow(
            title: listing.title,
            snippet:
                '${listing.type.title} - ${listing.displayPrice.toInt()} BDT/${listing.cheapestPlan?.shortUnit ?? ''}',
            onTap: () => widget.onListingTap?.call(listing),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            listing.available
                ? BitmapDescriptor.hueAzure
                : BitmapDescriptor.hueRed,
          ),
        ),
      );
    }

    // Add selected location marker
    if (_selectedLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('selected'),
          position: _selectedLocation!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        ),
      );
    }

    return markers;
  }

  Future<void> _goToMyLocation() async {
    setState(() => _isLoadingLocation = true);

    final position = await _locationService.getCurrentLocation();

    if (!mounted) return;
    setState(() => _isLoadingLocation = false);

    if (position != null && _controller != null) {
      final latLng = LatLng(position.latitude, position.longitude);
      await focusCamera(
        context,
        _controller,
        CameraUpdate.newLatLngZoom(latLng, 15),
      );
      widget.onTap?.call(position.latitude, position.longitude);
    } else if (mounted) {
      ModernBanner.showError(
          context, 'Could not get your location. Please check permissions.');
    }
  }

  /// Puts the map back on what it's showing: every result pin if there are any,
  /// otherwise the search centre. The recovery for a map that's been zoomed and
  /// dragged until nothing recognisable is left on screen.
  Future<void> _focusOnContent() {
    final mappable = mappableListings(widget.listings);
    final update = mappable.isEmpty
        ? CameraUpdate.newLatLngZoom(
            LatLng(widget.centerLat, widget.centerLng), 14)
        : framePoints(
            // The same coarsened points the pins use, so the fit frames what's
            // actually drawn.
            [for (final l in mappable) _pinFor(l)],
            padding: 48,
          );
    if (update == null) return Future<void>.value();
    return focusCamera(context, _controller, update);
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _selectedLocation = position;
    });
    widget.onTap?.call(position.latitude, position.longitude);
  }

  void _onCameraMove(CameraPosition position) {
    widget.onCameraMove
        ?.call(position.target.latitude, position.target.longitude);
  }

  @override
  void didUpdateWidget(MusafirMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centerLat != widget.centerLat ||
        oldWidget.centerLng != widget.centerLng) {
      _controller?.animateCamera(
        CameraUpdate.newLatLng(LatLng(widget.centerLat, widget.centerLng)),
      );
    }
  }

  @override
  void dispose() {
    // Only dispose controller if map was fully created (fixes web bug)
    if (_mapCreated && _controller != null) {
      _controller!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            WebDeferredMount(
              builder: (context) => GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(widget.centerLat, widget.centerLng),
                  zoom: 14,
                ),
                onMapCreated: (controller) {
                  _controller = controller;
                  _mapCreated = true;
                },
                onTap: _onMapTap,
                onCameraMove: _onCameraMove,
                markers: _markers,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: MapFocusControls(
                children: [
                  MapFocusButton(
                    icon: Icons.center_focus_strong_rounded,
                    label: widget.listings.isEmpty
                        ? 'Center the map on the search area'
                        : 'Show all results',
                    onPressed: _focusOnContent,
                  ),
                  if (widget.showMyLocationButton)
                    MapFocusButton(
                      icon: Icons.my_location_rounded,
                      label: 'Center on my location',
                      emphasized: true,
                      busy: _isLoadingLocation,
                      onPressed: _goToMyLocation,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
