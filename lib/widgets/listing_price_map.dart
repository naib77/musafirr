import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/privacy/listing_location.dart';
import '../core/theme/app_colors.dart';
import '../models/listing.dart';
import 'map_focus_button.dart';
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
    this.bottomInset = 0,
  });

  final List<Listing> listings;
  final void Function(Listing listing) onListingTap;

  /// Height (px) covered at the bottom by an overlay like the results sheet.
  /// Fed to Google Maps as camera `padding`, so the fit and the map's centre
  /// sit in the VISIBLE strip above the overlay instead of behind it — without
  /// it, a "Dhaka" fit centres under the sheet and only the area to the north
  /// shows. Zero for maps with nothing overlapping them.
  final double bottomInset;

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
          // Coarsened, not the exact building. Nobody browsing results has an
          // accepted booking for them, and an exact pin here would hand over
          // the address the listing page withholds. At city zoom the shift is
          // invisible; the guest sees the same spread of stays either way.
          position: _pinFor(listing),
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

  /// Where a listing's pill goes: the area, never the door. See
  /// [ListingLocation] for why the offset is a fixed grid and not random jitter.
  static LatLng _pinFor(Listing listing) {
    final at = ListingLocation.approximate(listing);
    return LatLng(at.latitude, at.longitude);
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

  /// Frames the result pins. Because the search is already filtered to the
  /// place (server-side bounding box), every pin sits inside the searched area,
  /// so framing the pins zooms right in on where the stays actually are —
  /// tighter and more useful than framing the whole city outline. The camera
  /// `padding` (set from the results sheet) keeps that framing in the visible
  /// strip above the sheet. A single stay (or several at one address) has no
  /// meaningful spread, so it gets a fixed neighbourhood-level zoom instead.
  Future<void> _fitToListings({bool animate = false}) async {
    final controller = _controller;
    if (controller == null || _mappable.isEmpty) return;

    // Tight padding (24, not the 48 default) so the pins fill the visible area
    // — the guest asked for a closer view. A lone/clustered result jumps to a
    // street-level zoom rather than a wide neighbourhood one.
    final update = framePoints(
      // Same coarsened points the pins use, so the fit frames what's drawn.
      [for (final l in _mappable) _pinFor(l)],
      padding: 24,
    );
    if (update == null) return;

    if (animate) {
      await focusCamera(context, controller, update);
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
        // Inset the camera so fits and gestures respect the strip left visible
        // above the results sheet, not the full rectangle it half-covers.
        padding: EdgeInsets.only(bottom: widget.bottomInset),
        myLocationButtonEnabled: false,
        mapToolbarEnabled: false,
        // Zoom must always be possible. The +/- control is the only way to
        // zoom with a plain mouse once wheel-zoom is held back below, and it
        // costs nothing on touch.
        zoomControlsEnabled: true,
        // Mobile: an inline map that pans would swallow the results list's
        // vertical drags. Pinch-zoom is a separate flag and stays on.
        scrollGesturesEnabled: widget.interactive,
        // Web reads its own flag and ignores the one above. `cooperative`
        // is the behaviour wanted inline: the page keeps scrolling, while
        // ctrl/⌘+wheel and two-finger gestures zoom the map. Passing this
        // explicitly is also the actual fix for zoom being dead — the plugin
        // collapses `scrollGesturesEnabled: false` into
        // `gestureHandling: none`, which disables *every* gesture including
        // zoom, unless webGestureHandling says otherwise.
        webGestureHandling: widget.interactive
            ? WebGestureHandling.greedy
            : WebGestureHandling.cooperative,
      ),
    );

    final inline = widget.height != null;
    final controls = <Widget>[
      // The inline map can't be panned, so offer the one that can.
      if (inline)
        MapFocusButton(
          icon: Icons.open_in_full_rounded,
          label: 'Open the full map',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ListingsMapScreen(
                listings: widget.listings,
                onListingTap: widget.onListingTap,
              ),
            ),
          ),
        ),
      // Zoom is enabled even inline, so a guest can lose the pins on either
      // map. This puts every result back in frame. Last, and so closest to the
      // thumb, because it's the one that rescues a lost map.
      MapFocusButton(
        icon: Icons.center_focus_strong_rounded,
        label: _mappable.length == 1
            ? 'Center the map on this stay'
            : 'Show all ${_mappable.length} stays',
        emphasized: true,
        onPressed: () => _fitToListings(animate: true),
      ),
    ];

    final stack = LayoutBuilder(
      builder: (context, constraints) {
        // The controls ride above whatever overlaps the bottom of the map (the
        // results sheet), so they never end up underneath it. That sheet can be
        // dragged all the way up, though — once the strip it leaves is too
        // short to hold the stack, the controls go away rather than float off
        // the top of the map and over the sheet. Nothing left to re-frame by
        // then anyway.
        final diameter = MapFocusButton.diameterOf(context);
        final stackHeight =
            controls.length * diameter + (controls.length - 1) * 8;
        final visible = constraints.maxHeight - widget.bottomInset;

        return Stack(
          children: [
            Positioned.fill(child: map),
            if (visible >= stackHeight + 20)
              Positioned(
                right: 10,
                bottom: widget.bottomInset + 10,
                child: MapFocusControls(children: controls),
              ),
          ],
        );
      },
    );

    if (!inline) return stack;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(height: widget.height, child: stack),
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
