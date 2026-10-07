import '../services/contact_phone.dart';

/// A listing's real street address and coordinates.
///
/// Kept out of [Listing] on purpose. `public.listings` holds only the
/// area-level form — a database trigger derives its `address` from area/city and
/// snaps its coordinates to a ~110m grid, so the table structurally cannot hold
/// a door. The precise values live in `public.listing_addresses`, whose RLS
/// admits only the host, an admin, or a guest whose booking the host has
/// accepted.
///
/// So a null returned from `MusafirRepository.fetchListingExactAddress` is not
/// an error and not missing data: it is the server declining, and the caller
/// must fall back to the area. The server is the gate; the app's
/// `ListingLocation` only decides how to draw what the server allowed.
class ListingExactAddress {
  const ListingExactAddress({
    required this.listingId,
    this.houseNo,
    this.flatFloor,
    this.street,
    this.address,
    this.latitude,
    this.longitude,
    this.contactPhones = const [],
  });

  final String listingId;
  final String? houseNo;
  final String? flatFloor;
  final String? street;

  /// The full composed line as the host entered it.
  final String? address;

  /// 160/162. The host's contact numbers for this listing, `+880…`,
  /// disclosed on the same terms as the address (a column of the same row).
  /// Not part of [isEmpty]: a number alone is still a disclosure.
  final List<String> contactPhones;

  /// The real coordinates — not the snapped ones on [Listing].
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Nothing worth disclosing: no parts, no line, no point. A row like this
  /// carries no more than the listing already shows publicly.
  bool get isEmpty =>
      (address == null || address!.trim().isEmpty) &&
      (houseNo == null || houseNo!.trim().isEmpty) &&
      (flatFloor == null || flatFloor!.trim().isEmpty) &&
      (street == null || street!.trim().isEmpty) &&
      !hasCoordinates;

  factory ListingExactAddress.fromJson(Map<String, dynamic> json) {
    return ListingExactAddress(
      listingId: json['listing_id'] as String,
      houseNo: json['house_no'] as String?,
      flatFloor: json['flat_floor'] as String?,
      street: json['street'] as String?,
      address: json['exact_address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      contactPhones: contactPhonesFromJson(json['contact_phones']),
    );
  }

  Map<String, dynamic> toJson() => {
        'listing_id': listingId,
        'house_no': houseNo,
        'flat_floor': flatFloor,
        'street': street,
        'exact_address': address,
        'latitude': latitude,
        'longitude': longitude,
        // An empty list is stored as null: the column has one spelling for
        // "no numbers" (162).
        'contact_phones': contactPhones.isEmpty ? null : contactPhones,
      };
}
