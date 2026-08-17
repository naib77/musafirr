import '../../models/listing.dart';
import '../../models/listing_exact_address.dart';

/// Where a listing is — as much of it as the server was willing to disclose.
///
/// A full address names a specific door: house number, flat, road. Handing that
/// to everyone who opens a listing page tells strangers where a host lives and,
/// alongside the calendar, when the place is empty. The host decides who gets
/// it, and the way they say so is by accepting a booking.
///
/// **The gate is in the database, not here.** `public.listings` carries only the
/// area-level address, with coordinates snapped to a ~110m grid by a trigger, so
/// a browsing client never receives a precise location to leak in the first
/// place. The exact values live in `public.listing_addresses` behind RLS
/// (`can_see_listing_address()`: owner, admin, or a guest with a
/// confirmed/active/completed booking). This class only decides how to draw
/// whatever came back — see migration 093_listing_address_privacy.sql.
///
/// That is why there is no booking-status check in this file. Duplicating the
/// rule in Dart would give two answers that could drift, and only one of them
/// would be enforceable.
class ListingLocation {
  const ListingLocation._({
    required this.isExact,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  /// Resolves what to show from what the server handed over. [exact] is the
  /// result of `MusafirRepository.fetchListingExactAddress` — null means the
  /// server declined (or hasn't answered yet), which is the same thing as far as
  /// the guest is concerned: show the area.
  factory ListingLocation.forListing(
    Listing listing,
    ListingExactAddress? exact,
  ) {
    if (exact == null || exact.isEmpty) {
      return ListingLocation.approximate(listing);
    }
    return ListingLocation.disclosed(listing, exact);
  }

  /// The exact address, as disclosed by the server.
  factory ListingLocation.disclosed(
    Listing listing,
    ListingExactAddress exact,
  ) {
    final line = exact.address?.trim();
    return ListingLocation._(
      isExact: true,
      label: (line != null && line.isNotEmpty)
          ? line
          // No stored line (a row written from parts alone): compose one, taking
          // the door parts from the disclosure and the area parts from the
          // listing, which carries them publicly.
          : Listing.composeAddress(
              houseNo: exact.houseNo,
              flatFloor: exact.flatFloor,
              street: exact.street,
              area: listing.area,
              city: listing.city,
              postalCode: listing.postalCode,
            ),
      // Falls back to the listing's snapped point when the disclosure has no
      // coordinates of its own — better a slightly coarse pin than none.
      latitude: exact.latitude ?? listing.latitude,
      longitude: exact.longitude ?? listing.longitude,
      radiusMeters: null,
    );
  }

  /// The area only, with a circle instead of a pin.
  ///
  /// [Listing.latitude]/[Listing.longitude] already arrive snapped from the
  /// server; snapping again here is idempotent and keeps this correct for
  /// locally-built listings that never went through the database.
  factory ListingLocation.approximate(Listing listing) => ListingLocation._(
        isExact: false,
        label: listing.approximateAddress,
        latitude: snapCoordinate(listing.latitude),
        longitude: snapCoordinate(listing.longitude),
        radiusMeters: approximateRadiusMeters,
      );

  /// Whether [label] is the full address and [latitude]/[longitude] the real
  /// coordinates. False means both are area-level.
  final bool isExact;

  /// The address line to print.
  final String label;

  /// Where to put a marker ([isExact]) or the centre of the circle.
  final double latitude;
  final double longitude;

  /// Radius of the "somewhere in here" circle, in metres. Null when [isExact] —
  /// there is no uncertainty left to draw.
  final double? radiusMeters;

  /// Why the location is vague and what makes it precise. Null when [isExact].
  String? get disclosure => isExact
      ? null
      : 'For the host\'s privacy, only the area is shown. You\'ll get the '
          'full address once the host accepts your booking.';

  /// Radius of the circle drawn in place of a pin, in metres. Wide enough to
  /// hold a few blocks, so which building is which stays unknowable — and
  /// comfortably larger than the worst-case snapping offset (~78m).
  static const double approximateRadiusMeters = 300;

  /// Grid the approximate centre is snapped to, in degrees — roughly 110m of
  /// latitude, keeping the true position within ~55m of the centre per axis.
  ///
  /// **Must match `snap_coordinate()` in migration 093**, or the circle drawn
  /// here would be centred somewhere the server didn't intend.
  static const double gridDegrees = 0.001;

  /// Snaps a coordinate to a fixed grid.
  ///
  /// Deliberately not random jitter: a random offset re-rolled on every read can
  /// be averaged away over enough samples to recover the true point. A fixed
  /// grid gives the same answer every time and reveals nothing beyond which cell
  /// the listing is in.
  static double snapCoordinate(double degrees) =>
      (degrees / gridDegrees).roundToDouble() * gridDegrees;
}
