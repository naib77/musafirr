import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/theme/app_colors.dart';
import '../models/listing.dart';
import 'web_deferred_mount.dart';

/// The price on a listing's map marker: its cheapest rate in full — "৳500",
/// "৳1,500", "৳35,000". Exact, not compacted to "৳1.5K": on a map a guest is
/// comparing one pin against another, and rounded figures make two different
/// prices look identical. No unit and no paisa — a pill has room for a figure,
/// not a phrase, and the card below spells the units out.
String listingPriceLabel(Listing listing) {
  final money = listing.cheapestRateMoney;
  if (money == null || money.amount <= 0) return '—';
  return money.format(showDecimal: false);
}

/// Listings that can appear on a map. A listing with no coordinates (0,0 is
/// what the API sends when a host never placed a pin) would land in the Gulf
/// of Guinea and drag the camera bounds across the planet with it.
List<Listing> mappableListings(List<Listing> listings) {
  return listings
      .where((l) =>
          l.latitude != 0 &&
          l.longitude != 0 &&
          l.latitude.abs() <= 90 &&
          l.longitude.abs() <= 180)
      .toList();
}

/// A map of search results with a price pill on every listing, the way Airbnb
/// shows them. Sits above the results grid so a guest can see how the stays
/// are spread out before scrolling.
class ListingPriceMap extends StatefulWidget {
  const ListingPriceMap({
    super.key,
    required this.listings,
    required this.onListingTap,
    this.height = 240,
    this.interactive = false,
  });

  final List<Listing> listings;
  final void Function(Listing listing) onListingTap;

  /// Fixed height for the inline map; null fills the available space, which is
  /// what the full-screen map wants.
  final double? height;

  /// Whether the guest can pan the map. False inline — inside a scrolling list
  /// a pannable map swallows vertical drags and traps the scroll — and true on
  /// the full-screen map, which has no competing scroll view.
  final bool interactive;

  @override
  State<ListingPriceMap> createState() => _ListingPriceMapState();
}

class _ListingPriceMapState extends State<ListingPriceMap> {
  GoogleMapController? _controller;
  bool _mapCreated = false;

  /// Painted pills, keyed by "label|selected" — a search of 50 stays usually
  /// holds only a handful of distinct prices, so this keeps the raster work
  /// down to a few images instead of one per marker.
  final Map<String, BitmapDescriptor> _pills = {};

  Set<Marker> _markers = {};
  String? _selectedId;
  List<Listing> _mappable = const [];

  /// Device pixel ratio the pills were painted at. Read in
  /// [didChangeDependencies], never in [initState]: MediaQuery is an inherited
  /// widget, and reading one during initState throws — which silently left the
  /// map with no markers at all.
  double _dpr = 0;

  bool _fittedOnce = false;

  @override
  void initState() {
    super.initState();
    _mappable = mappableListings(widget.listings);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    if (dpr != _dpr) {
      // Also covers a window dragged to a screen of a different density: the
      // cached pills were rasterised for the old ratio.
      _dpr = dpr;
      _pills.clear();
      _rebuildMarkers();
    }
  }

  @override
  void didUpdateWidget(ListingPriceMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameListings(oldWidget.listings, widget.listings)) {
      _mappable = mappableListings(widget.listings);
      if (_selectedId != null && !_mappable.any((l) => l.id == _selectedId)) {
        _selectedId = null;
      }
      _rebuildMarkers();
      _fitToListings(animate: true);
    }
  }

  bool _sameListings(List<Listing> a, List<Listing> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  void dispose() {
    // Matches MusafirMap: disposing a controller for a map that never finished
    // creating throws on web.
    if (_mapCreated) _controller?.dispose();
    super.dispose();
  }

  Future<void> _rebuildMarkers() async {
    final dpr = _dpr == 0 ? 2.0 : _dpr;
    final markers = <Marker>{};

    for (final listing in _mappable) {
      final selected = listing.id == _selectedId;
      final label = listingPriceLabel(listing);
      final icon = await _pill(label, selected: selected, dpr: dpr);
      if (!mounted) return;
      markers.add(
        Marker(
          markerId: MarkerId(listing.id),
          position: LatLng(listing.latitude, listing.longitude),
          icon: icon,
          // Selected pill draws above its neighbours so it isn't half-hidden
          // by a cheaper stay next door.
          zIndexInt: selected ? 2 : 1,
          anchor: const Offset(0.5, 0.5),
          consumeTapEvents: true,
          onTap: () => _onMarkerTap(listing),
        ),
      );
    }

    if (!mounted) return;
    setState(() => _markers = markers);
  }

  void _onMarkerTap(Listing listing) {
    setState(() => _selectedId = listing.id);
    _rebuildMarkers();
    widget.onListingTap(listing);
  }

  /// Paints a rounded price pill and hands it over as a PNG. [dpr] keeps the
  /// text crisp on high-density screens: the image is rasterised that many
  /// times larger and declared as such, so the platform scales it back down.
  Future<BitmapDescriptor> _pill(
    String label, {
    required bool selected,
    required double dpr,
  }) async {
    final key = '$label|$selected';
    final cached = _pills[key];
    if (cached != null) return cached;

    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : AppColors.ink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padH = 11.0;
    const padV = 6.0;
    final width = painter.width + padH * 2;
    final height = painter.height + padV * 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(dpr);

    final rect = Rect.fromLTWH(0, 0, width, height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(height / 2));
    // Shadow only, no outline: it's what lifts the pill off the map without
    // the boxed-in look an outline gives at this size.
    canvas
      ..drawShadow(Path()..addRRect(rrect), Colors.black54, 1.5, false)
      ..drawRRect(
        rrect,
        Paint()..color = selected ? AppColors.brand : Colors.white,
      );
    painter.paint(canvas, const Offset(padH, padV));

    final image = await recorder.endRecording().toImage(
          (width * dpr).ceil(),
          (height * dpr).ceil(),
        );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    // A renderer that can't hand back PNG bytes shouldn't cost the guest every
    // marker: fall back to a stock pin so the stays are still on the map.
    if (bytes == null) return BitmapDescriptor.defaultMarker;

    final descriptor = BytesMapBitmap(
      bytes.buffer.asUint8List(),
      imagePixelRatio: dpr,
    );
    _pills[key] = descriptor;
    return descriptor;
  }

  /// Frames every result. A single stay (or several at one address) has no
  /// meaningful bounds, so it gets a fixed neighbourhood-level zoom instead.
  Future<void> _fitToListings({bool animate = false}) async {
    final controller = _controller;
    if (controller == null || _mappable.isEmpty) return;

    var minLat = _mappable.first.latitude;
    var maxLat = minLat;
    var minLng = _mappable.first.longitude;
    var maxLng = minLng;
    for (final l in _mappable) {
      minLat = l.latitude < minLat ? l.latitude : minLat;
      maxLat = l.latitude > maxLat ? l.latitude : maxLat;
      minLng = l.longitude < minLng ? l.longitude : minLng;
      maxLng = l.longitude > maxLng ? l.longitude : maxLng;
    }

    final update = (maxLat - minLat < 0.002 && maxLng - minLng < 0.002)
        ? CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 14)
        : CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng),
            ),
            48,
          );

    if (animate) {
      await controller.animateCamera(update);
    } else {
      await controller.moveCamera(update);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mappable.isEmpty) return const SizedBox.shrink();

    final first = _mappable.first;
    final map = WebDeferredMount(
      builder: (context) => GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(first.latitude, first.longitude),
          zoom: 12,
        ),
        onMapCreated: (controller) {
          _controller = controller;
          _mapCreated = true;
          _fitToListings();
        },
        // On web the map is sometimes still sizing itself when onMapCreated
        // fires, and a bounds fit applied then lands on the wrong zoom. Fit
        // once more when the camera first settles; after that this is inert,
        // so panning the full-screen map is never yanked back.
        onCameraIdle: () {
          if (_fittedOnce) return;
          _fittedOnce = true;
          _fitToListings();
        },
        markers: _markers,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        scrollGesturesEnabled: widget.interactive,
      ),
    );

    if (widget.height == null) return map;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(child: map),
            // The inline map can't be panned, so offer the one that can.
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ListingsMapScreen(
                        listings: widget.listings,
                        onListingTap: widget.onListingTap,
                      ),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(Icons.open_in_full_rounded,
                        size: 18, color: AppColors.ink),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The results map full-screen, where it can actually be panned and zoomed.
class ListingsMapScreen extends StatelessWidget {
  const ListingsMapScreen({
    super.key,
    required this.listings,
    required this.onListingTap,
  });

  final List<Listing> listings;
  final void Function(Listing listing) onListingTap;

  @override
  Widget build(BuildContext context) {
    final count = mappableListings(listings).length;
    return Scaffold(
      appBar: AppBar(
        title: Text('$count ${count == 1 ? 'stay' : 'stays'} on the map'),
      ),
      body: ListingPriceMap(
        listings: listings,
        height: null,
        interactive: true,
        // Opening a listing from here keeps the map underneath, so closing the
        // listing returns to the same view.
        onListingTap: onListingTap,
      ),
    );
  }
}
